defmodule Aac.Business.DataKeeper do
  @moduledoc """
  Central data management engine for all configuration and authorization data.
  Port of Python's configDataKeeper class.

  Handles: users, branches, roles, funcsets, employees, agents, functions.
  All public functions return {:ok, map} or {:error, reason, map}.
  """
  import Ecto.Query
  alias Aac.Repo
  alias Aac.Schema.{User, UserChange, Branch, BranchWhitelist, Funcset, FuncsetFunction,
                     Role, RoleFuncset, Employee, Agent, AgentTag, FunctionDef}
  require Logger
  require Record

  Record.defrecordp(:xmlDocument, Record.extract(:xmlDocument, from_lib: 'xmerl/include/xmerl.hrl'))
  Record.defrecordp(:xmlElement, Record.extract(:xmlElement, from_lib: 'xmerl/include/xmerl.hrl'))
  Record.defrecordp(:xmlAttribute, Record.extract(:xmlAttribute, from_lib: 'xmerl/include/xmerl.hrl'))

  # ── Identifier validation (XPath injection equivalent) ──

  @safe_id_re ~r/^[\w\-\.@\+ ]{0,256}$/u

  defp safe_value!(nil), do: nil
  defp safe_value!(value) do
    s = to_string(value)
    if Regex.match?(@safe_id_re, s), do: s,
    else: raise ArgumentError, "Unsafe characters in identifier: #{inspect(s)}"
  end

  # ── Result helpers ──

  defp ok(extra \\ %{}), do: Map.merge(%{"result" => true}, extra)
  defp err(reason, warning, extra \\ %{}), do: Map.merge(%{"result" => false, "reason" => reason, "warning" => warning}, extra)

  # ── Users ──

  def list_users do
    ids = Repo.all(from u in User, select: u.id, order_by: u.id)
    ok(%{"users" => ids})
  end

  def get_user_reg_details(nil), do: err("WRONG-FORMAT", "Not all required parameters are given: user id is nil")
  def get_user_reg_details(userid, app_name \\ nil) do
    case Repo.get(User, userid) do
      nil ->
        err("USER-UNKNOWN", "User '#{userid}' is unknown")
      user ->
        user = Repo.preload(user, :changes)
        ret = ok(%{
          "secret_changed" => user.psw_changed_at,
          "secret_expiration" => user.expire_at || 0,
          "readable_name" => user.readable_name || "",
          "session_max" => user.session_max || default_session_max(),
          "created" => [user.created_by || "", user.created_at && to_string(user.created_at) || ""],
          "change_history" => Enum.map(user.changes, &[&1.changed_by, to_string(&1.changed_at)])
        })
        if app_name not in [nil, ""] do
          add_app_details(ret, app_name, userid)
        else
          ret
        end
    end
  end

  defp add_app_details(ret, app_name, userid) do
    ret = Map.put(ret, "for_application", app_name)

    case app_name do
      "gAP" ->
        branches = user_branches(userid)
        ret
        |> Map.put("branches", branches)
        |> Map.put("positions", user_positions(userid))
        |> Map.put("func_groups", user_funcsets(userid))
        |> Map.put("functions", emp_function_details(userid, "id,callpath,method"))
        |> Map.put("agents", if(branches == [], do: [], else: list_agents_report(hd(branches), true, false)))

      "thePage" ->
        funcset_ids = user_funcsets(userid)
        funcsets_map = funcset_ids
          |> Enum.reduce(%{}, fn fs_id, acc ->
            case get_funcset_details(fs_id) do
              %{"result" => true} = det ->
                functions = Enum.map(det["functions"], fn fi ->
                  case review_functions("id,name,title", fi) do
                    %{"result" => true, "props" => props} -> props
                    _ -> %{"id" => fi, "name" => "UNDESCRIBED #{fi}", "title" => "UNDESCRIBED #{fi}"}
                  end
                end)
                Map.put(acc, fs_id, %{"name" => det["name"], "functions" => functions})
              _ -> acc
            end
          end)
        Map.put(ret, "funcsets", funcsets_map)

      _ -> ret
    end
  end

  # ── Authentication ──

  def authorize(userid, secret, app_name) do
    if secret == nil do
      err("WRONG-FORMAT", "Not all required parameters are given: secret is nil")
    else
      ret = get_user_reg_details(userid, app_name)
      if ret["result"] do
        case Repo.get(User, userid) do
          nil -> ret
          user ->
            failures = user.failures || 0
            cond do
              secret != user.secret ->
                new_failures = failures + 1
                update_user_failure(user, new_failures)
                err("WRONG-SECRET", "User '#{userid}' made #{new_failures} password mistake(s)", %{"failures" => new_failures})

              user.expire_at && user.expire_at > 0 && System.os_time(:second) > user.expire_at ->
                new_failures = failures + 1
                update_user_failure(user, new_failures)
                err("SECRET-EXPIRED", "Password of '#{userid}' expired", %{"secret_expiration" => user.expire_at, "failures" => new_failures})

              true ->
                now = System.os_time(:second)
                User.changeset(user, %{failures: 0, last_auth_success: now})
                |> Repo.update()
                Logger.info("User '#{userid}' authenticated")
                ret
            end
        end
      else
        ret
      end
    end
  end

  defp update_user_failure(user, failures) do
    now = System.os_time(:second)
    User.changeset(user, %{failures: failures, last_error: now})
    |> Repo.update()
  end

  # ── User CRUD ──

  def create_user(userid, secret, operator, psw_lifetime \\ nil, readable_name \\ "", session_max \\ nil) do
    cond do
      any_nil?([userid, secret, operator]) ->
        err("WRONG-FORMAT", "Not all required parameters are given")
      Repo.get(User, userid) != nil ->
        err("ALREADY-EXISTS", "User '#{userid}' already exists")
      Repo.get(User, operator) == nil ->
        err("OP-UNKNOWN", "Operator #{inspect(operator)} is unknown to the system")
      true ->
        now = System.os_time(:second)
        sessmax = parse_int(session_max) || default_session_max()
        attrs = %{
          id: userid, secret: secret, psw_changed_at: now, failures: 0,
          readable_name: readable_name || "", session_max: sessmax,
          created_by: operator, created_at: now
        }
        attrs = if psw_lifetime not in [nil, ""] do
          exp = now + trunc(parse_float(psw_lifetime) * 86400)
          Map.put(attrs, :expire_at, exp)
        else
          attrs
        end

        case %User{} |> User.changeset(attrs) |> Repo.insert() do
          {:ok, _} ->
            ret = ok(%{"secret_changed" => now})
            if attrs[:expire_at], do: Map.put(ret, "secret_expiration", attrs[:expire_at]), else: ret
          {:error, cs} ->
            err("DATABASE-ERROR", "Insert failed: #{inspect(cs.errors)}")
        end
    end
  end

  def change_user(userid, secret, operator, psw_lifetime \\ nil, readable_name \\ "", session_max \\ nil) do
    cond do
      any_nil?([userid, secret, operator]) ->
        err("WRONG-FORMAT", "Not all required parameters are given")
      true ->
        case Repo.get(User, userid) do
          nil -> err("USER-UNKNOWN", "User #{inspect(userid)} is unknown")
          user ->
            if Repo.get(User, operator) == nil do
              err("OP-UNKNOWN", "Operator #{inspect(operator)} is unknown to the system")
            else
              now = System.os_time(:second)
              sessmax = parse_int(session_max) || default_session_max()
              attrs = %{
                secret: secret, psw_changed_at: now, failures: 0,
                readable_name: readable_name || "", session_max: sessmax
              }
              attrs = if psw_lifetime not in [nil, ""] do
                exp = now + trunc(parse_float(psw_lifetime) * 86400)
                Map.put(attrs, :expire_at, exp)
              else
                Map.put(attrs, :expire_at, nil)
              end

              User.changeset(user, attrs) |> Repo.update()
              Repo.insert!(%UserChange{user_id: userid, changed_by: operator, changed_at: now})
              ret = ok(%{"secret_changed" => now})
              if attrs[:expire_at], do: Map.put(ret, "secret_expiration", attrs[:expire_at]), else: ret
            end
        end
    end
  end

  def delete_user(userid, operator) do
    cond do
      operator == nil || Repo.get(User, operator) == nil ->
        err("OP-UNKNOWN", "Operator #{inspect(operator)} is unknown to the system")
      userid == nil ->
        err("WRONG-FORMAT", "Not all required parameters are given: user id is nil")
      Repo.get(User, userid) == nil ->
        err("USER-UNKNOWN", "User #{inspect(userid)} is unknown")
      user_branches(userid) != [] ->
        err("USER-EMPLOYED", "User '#{userid}' is employed, fire him first")
      true ->
        Repo.get!(User, userid) |> Repo.delete()
        ok()
    end
  end

  # ── Funcsets ──

  def get_funcsets do
    Repo.all(from f in Funcset, select: f.id, order_by: f.id)
  end

  def funcset_create(branch_id, funcset_id, readable_name) do
    cond do
      funcset_id in [nil, ""] ->
        err("WRONG-FORMAT", "Required argument not given: funcset is #{inspect(funcset_id)}")
      !branch_exists?(branch_id) ->
        err("BRANCH-UNKNOWN", "Branch #{inspect(branch_id)} is unknown")
      Repo.get(Funcset, funcset_id) != nil ->
        err("ALREADY-EXISTS", "Funcset #{inspect(funcset_id)} already defined somewhere", %{"bad_value" => funcset_id})
      true ->
        %Funcset{id: safe_value!(funcset_id), name: readable_name || "", branch_id: branch_id}
        |> Repo.insert()
        ok()
    end
  end

  def funcset_delete(funcset_id) do
    case get_funcset_node(funcset_id) do
      {:error, r} -> r
      {:ok, fs} -> Repo.delete!(fs); ok()
    end
  end

  def get_funcset_details(funcset_id) do
    case get_funcset_node(funcset_id) do
      {:error, r} -> r
      {:ok, fs} ->
        func_ids = Repo.all(from ff in FuncsetFunction, where: ff.funcset_id == ^funcset_id, select: ff.function_id)
        ok(%{"functions" => func_ids, "name" => fs.name || "", "id" => funcset_id})
    end
  end

  def funcset_func_add(funcset_id, func_id) do
    with {:ok, _fs} <- get_funcset_node(funcset_id),
         :ok <- validate_not_empty(func_id, "function name") do
      safe_func = safe_value!(func_id)
      exists = Repo.exists?(from ff in FuncsetFunction, where: ff.funcset_id == ^funcset_id and ff.function_id == ^safe_func)
      if exists do
        err("ALREADY-EXISTS", "Function #{inspect(func_id)} already in #{inspect(funcset_id)}", %{"bad_value" => func_id})
      else
        Repo.insert!(%FuncsetFunction{funcset_id: funcset_id, function_id: safe_func})
        ok()
      end
    else
      {:error, r} -> r
    end
  end

  def funcset_func_remove(funcset_id, func_id) do
    with {:ok, _fs} <- get_funcset_node(funcset_id),
         :ok <- validate_not_empty(func_id, "function name") do
      safe_func = safe_value!(func_id)
      q = from ff in FuncsetFunction, where: ff.funcset_id == ^funcset_id and ff.function_id == ^safe_func
      case Repo.one(q) do
        nil -> err("NOT-IN-SET", "Function #{inspect(func_id)} is not in #{inspect(funcset_id)}", %{"bad_value" => func_id})
        ff -> Repo.delete!(ff); ok()
      end
    else
      {:error, r} -> r
    end
  end

  defp get_funcset_node(funcset_id) do
    cond do
      funcset_id in [nil, ""] -> {:error, err("WRONG-FORMAT", "Required funcset id is not given")}
      true ->
        case Repo.get(Funcset, funcset_id) do
          nil -> {:error, err("FUNCSET-UNKNOWN", "Funcset #{inspect(funcset_id)} is unknown", %{"bad_value" => funcset_id})}
          fs -> {:ok, fs}
        end
    end
  end

  # ── Branches ──

  def list_branches do
    Repo.all(from b in Branch, select: b.id, order_by: b.id)
  end

  def get_branch_subs(branch_id) do
    if branch_id == "" do
      ok(%{"branches" => list_branches()})
    else
      if branch_exists?(branch_id) do
        subs = get_all_descendant_ids(branch_id)
        ok(%{"branches" => Enum.sort(subs)})
      else
        err("BRANCH-UNKNOWN", "Branch #{inspect(branch_id)} is unknown", %{"bad_value" => branch_id})
      end
    end
  end

  def add_branch_sub(branch_id, sub_id) do
    cond do
      !branch_exists?(branch_id) ->
        err("BRANCH-UNKNOWN", "Branch #{inspect(branch_id)} is unknown", %{"bad_value" => branch_id})
      sub_id in [nil, ""] ->
        err("WRONG-FORMAT", "Required argument not given: subbranch is #{inspect(sub_id)}")
      branch_exists?(sub_id) ->
        err("ALREADY-EXISTS", "Branch #{inspect(branch_id)} already has subbranch #{inspect(sub_id)}", %{"bad_value" => sub_id})
      true ->
        %Branch{id: safe_value!(sub_id), parent_id: branch_id, propagate_parent: false}
        |> Repo.insert!()
        ok()
    end
  end

  def delete_branch(branch_id) do
    case Repo.get(Branch, branch_id) do
      nil ->
        err("BRANCH-UNKNOWN", "Branch #{inspect(branch_id)} is unknown")
      branch ->
        if branch.parent_id == nil do
          err("NOT-ALLOWED", "Deletion of a root branch #{inspect(branch_id)} is not allowed", %{"bad_value" => branch_id})
        else
          # Check for employees in branch and descendants
          all_ids = [branch_id | get_all_descendant_ids(branch_id)]
          emps = Repo.all(from e in Employee, where: e.branch_id in ^all_ids and not is_nil(e.person_id), select: e.person_id)
          if emps != [] do
            err("USER-EMPLOYED", "Branch #{inspect(branch_id)} still has employees: #{inspect(emps)}", %{"fire_them" => emps})
          else
            Repo.delete!(branch)
            ok()
          end
        end
    end
  end

  def get_branch_fs_whitelist(branch_id) do
    case Repo.get(Branch, branch_id) do
      nil -> err("BRANCH-UNKNOWN", "Branch #{inspect(branch_id)} is unknown")
      branch ->
        wl = Repo.all(from w in BranchWhitelist, where: w.branch_id == ^branch_id, select: w.funcset_id, order_by: w.funcset_id)
        ok(%{"funcsets" => wl, "propagate_parent_flag" => branch.propagate_parent})
    end
  end

  def set_branch_fs_whitelist(branch_id, prop_parent_flag, new_wlist) do
    case Repo.get(Branch, branch_id) do
      nil -> err("BRANCH-UNKNOWN", "Branch #{inspect(branch_id)} is unknown")
      branch ->
        Branch.changeset(branch, %{propagate_parent: prop_parent_flag}) |> Repo.update!()
        Repo.delete_all(from w in BranchWhitelist, where: w.branch_id == ^branch_id)
        Enum.each(new_wlist, fn fs_id ->
          Repo.insert!(%BranchWhitelist{branch_id: branch_id, funcset_id: fs_id})
        end)
        ok()
    end
  end

  def review_branches(pos \\ "") do
    branches = if pos == "" do
      Repo.all(from b in Branch, select: b.id)
    else
      safe_pos = safe_value!(pos)
      Repo.all(from b in Branch,
        join: e in Employee, on: e.branch_id == b.id,
        where: e.position == ^safe_pos,
        distinct: true,
        select: b.id)
    end

    Enum.map(branches, fn bid ->
      vacancies = if pos == "" do
        Repo.all(from e in Employee, where: e.branch_id == ^bid and is_nil(e.person_id), select: e.position)
      else
        safe_pos = safe_value!(pos)
        Repo.all(from e in Employee, where: e.branch_id == ^bid and is_nil(e.person_id) and e.position == ^safe_pos, select: e.position)
      end
      %{"id" => bid, "vacancies" => vacancies}
    end)
  end

  def get_branches(pos \\ "") do
    branches = review_branches(pos)
    Enum.map(branches, fn b ->
      %{"id" => b["id"], "value" => "#{b["id"]} - #{length(b["vacancies"])} vacancies"}
    end)
  end

  # ── Roles ──

  def list_roles_4_branch(branch_id) do
    safe_id = safe_value!(branch_id)
    Repo.all(from r in Role, where: r.branch_id == ^safe_id, select: r.name, distinct: true)
  end

  def list_enabled_roles_4_branch(branch_id) do
    if !branch_exists?(branch_id) do
      []
    else
      ancestor_ids = get_ancestor_ids(branch_id) ++ [branch_id]
      Repo.all(from r in Role, where: r.branch_id in ^ancestor_ids, select: r.name, distinct: true)
      |> Enum.sort()
    end
  end

  def list_branch_roles(branch_id, with_inherited, with_branchids) do
    case Repo.get(Branch, branch_id) do
      nil -> err("BRANCH-UNKNOWN", "Branch #{inspect(branch_id)} is unknown")
      _branch ->
        scope_ids = if with_inherited do
          get_ancestor_ids(branch_id) ++ [branch_id]
        else
          [branch_id]
        end

        roles = Repo.all(from r in Role, where: r.branch_id in ^scope_ids, select: {r.name, r.branch_id}, distinct: true)

        if with_branchids do
          # For each role name, find the closest definition (closest = last in ancestor order)
          role_names = roles |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
          ordered_scope = get_ancestor_ids(branch_id) ++ [branch_id]

          roles_in_branch = Enum.map(role_names, fn name ->
            matching = Enum.filter(roles, fn {n, _b} -> n == name end)
            # Pick the closest branch (last in ancestor chain)
            closest = Enum.max_by(matching, fn {_n, bid} ->
              Enum.find_index(ordered_scope, &(&1 == bid)) || -1
            end)
            [elem(closest, 0), elem(closest, 1)]
          end) |> Enum.sort_by(&hd/1)

          ok(%{"roles_in_branch" => roles_in_branch})
        else
          ok(%{"roles" => roles |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.sort()})
        end
    end
  end

  def create_branch_role(branch_id, role_name, duties \\ []) do
    cond do
      !branch_exists?(branch_id) ->
        err("BRANCH-UNKNOWN", "Branch #{inspect(branch_id)} is unknown")
      role_name in [nil, ""] ->
        err("WRONG-FORMAT", "Required argument not given: role is #{inspect(role_name)}")
      true ->
        safe_name = safe_value!(role_name)
        exists = Repo.exists?(from r in Role, where: r.branch_id == ^branch_id and r.name == ^safe_name)
        if exists do
          err("ALREADY-EXISTS", "Role #{inspect(role_name)} already defined in branch #{inspect(branch_id)}", %{"bad_value" => role_name})
        else
          {:ok, role} = Repo.insert(%Role{name: safe_name, branch_id: branch_id})
          Enum.each(duties, fn d ->
            Repo.insert!(%RoleFuncset{role_id: role.id, funcset_id: d})
          end)
          ok()
        end
    end
  end

  def delete_branch_role(branch_id, role_name) do
    cond do
      !branch_exists?(branch_id) ->
        err("BRANCH-UNKNOWN", "Branch #{inspect(branch_id)} is unknown")
      role_name in [nil, ""] ->
        err("WRONG-FORMAT", "Required argument not given: role is #{inspect(role_name)}")
      true ->
        safe_name = safe_value!(role_name)
        case Repo.one(from r in Role, where: r.branch_id == ^branch_id and r.name == ^safe_name) do
          nil -> err("ROLE-UNKNOWN", "Role #{inspect(role_name)} has no direct definition in branch #{inspect(branch_id)}", %{"bad_value" => role_name})
          role -> Repo.delete!(role); ok()
        end
    end
  end

  def list_role_funcsets(branch_id, role_name) do
    with {:ok, role} <- find_role_node(branch_id, role_name) do
      fs_ids = Repo.all(from rf in RoleFuncset, where: rf.role_id == ^role.id, select: rf.funcset_id)
      ok(%{"funcsets" => fs_ids})
    else
      {:error, r} -> r
    end
  end

  def role_funcset_add(branch_id, role_name, funcset_id) do
    with {:ok, role} <- find_role_node(branch_id, role_name) do
      exists = Repo.exists?(from rf in RoleFuncset, where: rf.role_id == ^role.id and rf.funcset_id == ^funcset_id)
      if exists do
        err("ALREADY-EXISTS", "Funcset #{inspect(funcset_id)} already in role #{inspect(role_name)} of #{inspect(branch_id)}")
      else
        Repo.insert!(%RoleFuncset{role_id: role.id, funcset_id: funcset_id})
        ok()
      end
    else
      {:error, r} -> r
    end
  end

  def role_funcset_remove(branch_id, role_name, funcset_id) do
    with {:ok, role} <- find_role_node(branch_id, role_name) do
      case Repo.one(from rf in RoleFuncset, where: rf.role_id == ^role.id and rf.funcset_id == ^funcset_id) do
        nil -> err("NOT-IN-SET", "Funcset #{inspect(funcset_id)} is not in role #{inspect(role_name)} of #{inspect(branch_id)}")
        rf -> Repo.delete!(rf); ok()
      end
    else
      {:error, r} -> r
    end
  end

  defp find_role_node(branch_id, role_name) do
    cond do
      !branch_exists?(branch_id) ->
        {:error, err("BRANCH-UNKNOWN", "Branch #{inspect(branch_id)} is unknown")}
      role_name in [nil, ""] ->
        {:error, err("WRONG-FORMAT", "Required argument not given: role is #{inspect(role_name)}")}
      true ->
        safe_name = safe_value!(role_name)
        case Repo.one(from r in Role, where: r.branch_id == ^branch_id and r.name == ^safe_name) do
          nil -> {:error, err("ROLE-UNKNOWN", "Role #{role_name} not defined in branch #{branch_id}")}
          role -> {:ok, role}
        end
    end
  end

  # Find the closest role definition up the ancestor chain
  defp find_role_in_ancestors(role_name, branch_id) do
    safe_name = safe_value!(role_name)
    chain = [branch_id | get_ancestor_ids(branch_id)] |> Enum.reverse()
    # chain is root-first; we want closest = last
    chain = Enum.reverse(chain)

    Enum.find_value(chain, fn bid ->
      Repo.one(from r in Role, where: r.branch_id == ^bid and r.name == ^safe_name)
    end)
  end

  # ── Employees / Positions ──

  def create_branch_position(branch_id, role) do
    cond do
      !branch_exists?(branch_id) ->
        err("BRANCH-UNKNOWN", "Branch #{inspect(branch_id)} is unknown")
      role in [nil, ""] ->
        err("WRONG-FORMAT", "Required argument not given: role is #{inspect(role)}")
      true ->
        safe_role = safe_value!(role)
        Repo.insert!(%Employee{branch_id: branch_id, position: safe_role})
        total = Repo.aggregate(from(e in Employee, where: e.branch_id == ^branch_id and e.position == ^safe_role), :count)
        vacant = Repo.aggregate(from(e in Employee, where: e.branch_id == ^branch_id and e.position == ^safe_role and is_nil(e.person_id)), :count)
        ok(%{"branch" => branch_id, "pos" => role, "total" => total, "vacant" => vacant})
    end
  end

  def delete_branch_position(branch_id, role) do
    cond do
      !branch_exists?(branch_id) ->
        err("BRANCH-UNKNOWN", "Branch #{inspect(branch_id)} is unknown")
      role in [nil, ""] ->
        err("WRONG-FORMAT", "Required argument not given: role is #{inspect(role)}")
      true ->
        safe_role = safe_value!(role)
        case Repo.one(from e in Employee, where: e.branch_id == ^branch_id and e.position == ^safe_role and is_nil(e.person_id), limit: 1) do
          nil -> err("NOT-IN-SET", "Branch #{inspect(branch_id)} has no vacant #{inspect(role)} positions")
          emp ->
            Repo.delete!(emp)
            total = Repo.aggregate(from(e in Employee, where: e.branch_id == ^branch_id and e.position == ^safe_role), :count)
            vacant = Repo.aggregate(from(e in Employee, where: e.branch_id == ^branch_id and e.position == ^safe_role and is_nil(e.person_id)), :count)
            ok(%{"branch" => branch_id, "pos" => role, "total" => total, "vacant" => vacant})
        end
    end
  end

  def get_branch_vacant_positions(branch_id) do
    safe_id = safe_value!(branch_id)
    Repo.all(from e in Employee,
      where: e.branch_id == ^safe_id and is_nil(e.person_id),
      select: e.position,
      distinct: true,
      order_by: e.position)
  end

  def hire_employee(userid, branch_id, pos, operator) do
    cond do
      any_empty?([userid, branch_id, pos]) ->
        err("WRONG-FORMAT", "Not all required parameters are given")
      Repo.get(User, userid) == nil ->
        err("USER-UNKNOWN", "User #{inspect(userid)} is unknown")
      user_branches(userid) != [] ->
        err("ALREADY-EMPLOYED", "User '#{userid}' already employed at #{inspect(user_branches(userid))}")
      !branch_exists?(branch_id) ->
        err("BRANCH-UNKNOWN", "Branch '#{branch_id}' does not exist")
      true ->
        safe_pos = safe_value!(pos)
        case Repo.one(from e in Employee, where: e.branch_id == ^branch_id and e.position == ^safe_pos and is_nil(e.person_id), limit: 1) do
          nil ->
            err("NO-VACANT-POSITIONS", "No vacant positions for '#{pos}' in '#{branch_id}'")
          emp ->
            # Check operator authority
            case check_operator_branch_authority(operator, branch_id) do
              :ok ->
                Employee.changeset(emp, %{person_id: userid}) |> Repo.update!()
                ok()
              {:error, r} -> r
            end
        end
    end
  end

  def fire_employee(userid, operator) do
    cond do
      userid == nil ->
        err("WRONG-FORMAT", "Not all required parameters are given: user id is nil")
      Repo.get(User, userid) == nil ->
        err("USER-UNKNOWN", "User #{inspect(userid)} is unknown")
      user_branches(userid) == [] ->
        err("ALREADY-UNEMPLOYED", "User '#{userid}' already unemployed")
      true ->
        emp = Repo.one!(from e in Employee, where: e.person_id == ^userid, limit: 1)
        branch = emp.branch_id

        case check_operator_employee_authority(operator, userid) do
          :ok ->
            pos = emp.position
            Employee.changeset(emp, %{person_id: nil}) |> Repo.update!()
            ok(%{"branch" => branch, "pos" => pos})
          {:error, r} -> r
        end
    end
  end

  def branch_employees_list(branch_id, include_sub_branches) do
    safe_id = safe_value!(branch_id)
    if !branch_exists?(safe_id) do
      err("BRANCH-UNKNOWN", "Branch '#{branch_id}' is unknown")
    else
      branch_ids = if include_sub_branches do
        [safe_id | get_all_descendant_ids(safe_id)]
      else
        [safe_id]
      end
      emps = Repo.all(from e in Employee, where: e.branch_id in ^branch_ids and not is_nil(e.person_id), select: e.person_id)
      ok(%{"employees" => emps})
    end
  end

  def review_positions(branch_id \\ "") do
    q = if branch_id == "" do
      from e in Employee, select: %{pos: e.position, branch: e.branch_id, person_id: e.person_id}
    else
      safe_id = safe_value!(branch_id)
      from e in Employee, where: e.branch_id == ^safe_id, select: %{pos: e.position, branch: e.branch_id, person_id: e.person_id}
    end
    Repo.all(q) |> Enum.map(fn e ->
      %{"pos" => e.pos, "branch" => e.branch, "vacant" => e.person_id == nil}
    end)
  end

  def get_positions(branch_id \\ "") do
    q = if branch_id == "" do
      from e in Employee, select: %{pos: e.position, branch: e.branch_id, person_id: e.person_id}
    else
      safe_id = safe_value!(branch_id)
      from e in Employee, where: e.branch_id == ^safe_id, select: %{pos: e.position, branch: e.branch_id, person_id: e.person_id}
    end
    Repo.all(q) |> Enum.map(fn e ->
      status = if e.person_id == nil, do: "VACANT", else: "OCCUPIED"
      %{"id" => e.pos, "value" => "#{e.pos} at #{e.branch} #{status}"}
    end)
  end

  def get_branches_with_positions(branch_id, per_role, only_vacant) do
    branch_ids = if branch_id == "*ALL*" do
      list_branches()
    else
      [branch_id]
    end

    report = Enum.flat_map(branch_ids, fn bid ->
      q = from e in Employee, where: e.branch_id == ^bid
      q = if only_vacant, do: where(q, [e], is_nil(e.person_id)), else: q

      if per_role do
        positions = Repo.all(from e in subquery(q), select: e.position, distinct: true)
        Enum.map(positions, fn p ->
          count_q = from e in Employee, where: e.branch_id == ^bid and e.position == ^p
          count_q = if only_vacant, do: where(count_q, [e], is_nil(e.person_id)), else: count_q
          %{"branch" => bid, "role" => p, "count" => Repo.aggregate(count_q, :count)}
        end)
      else
        count_q = from e in Employee, where: e.branch_id == ^bid
        count_q = if only_vacant, do: where(count_q, [e], is_nil(e.person_id)), else: count_q
        count = Repo.aggregate(count_q, :count)
        if count > 0, do: [%{"branch" => bid, "count" => count}], else: []
      end
    end)

    ok(%{"branch_filter" => branch_id, "only_vacant" => only_vacant, "report" => report})
  end

  # ── Employee permissions ──

  def emp_subbranches_list(userid, all_levels, exclude_own) do
    if Repo.get(User, userid) == nil do
      err("USER-UNKNOWN", "User '#{userid}' is unknown")
    else
      emp_branches = user_branches(userid)
      sub_ids = Enum.flat_map(emp_branches, fn bid ->
        if all_levels, do: get_all_descendant_ids(bid), else: get_direct_children_ids(bid)
      end) |> MapSet.new()

      result = if exclude_own, do: sub_ids, else: MapSet.union(sub_ids, MapSet.new(emp_branches))
      ok(%{"subbranches" => MapSet.to_list(result)})
    end
  end

  def emp_funcsets_list(userid) do
    if Repo.get(User, userid) == nil do
      err("USER-UNKNOWN", "User '#{userid}' is unknown")
    else
      ok(%{"funcsets" => user_funcsets(userid)})
    end
  end

  def emp_functions_list(userid, prop \\ "id") do
    if Repo.get(User, userid) == nil do
      err("USER-UNKNOWN", "User '#{userid}' is unknown")
    else
      func_ids = emp_function_ids(userid)
      values = func_ids
        |> Enum.map(fn fid -> review_functions(prop, fid) end)
        |> Enum.filter(&(&1["result"]))
        |> Enum.map(&get_in(&1, ["props", prop]))
        |> Enum.uniq()
      ok(%{"prop" => prop, "functions" => values})
    end
  end

  def emp_functions_review(userid, props) do
    if Repo.get(User, userid) == nil do
      err("USER-UNKNOWN", "User '#{userid}' is unknown")
    else
      func_ids = emp_function_ids(userid)
      functions = func_ids
        |> Enum.map(fn fid -> review_functions(props, fid) end)
        |> Enum.filter(&(&1["result"]))
        |> Enum.map(& &1["props"])
      ok(%{"props" => props, "functions" => functions})
    end
  end

  defp emp_function_ids(userid) do
    funcset_ids = user_funcsets(userid)
    allowed = funcset_ids
      |> Enum.flat_map(fn fs_id ->
        Repo.all(from ff in FuncsetFunction, where: ff.funcset_id == ^fs_id, select: ff.function_id)
      end)
      |> MapSet.new()

    known = Repo.all(from f in FunctionDef, select: f.id) |> MapSet.new()
    MapSet.intersection(allowed, known) |> MapSet.to_list()
  end

  defp emp_function_details(userid, props) do
    emp_function_ids(userid)
    |> Enum.map(fn fid ->
      case review_functions(props, fid) do
        %{"result" => true, "props" => p} -> p
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  # ── Branch funcset collection (hierarchical whitelist resolution) ──

  def get_branch_enabled_funcsets(branch_id) do
    if !branch_exists?(branch_id), do: [],
    else: collect_branch_funcsets(branch_id) |> MapSet.to_list()
  end

  defp collect_branch_funcsets(branch_id) do
    defined_here = Repo.all(from f in Funcset, where: f.branch_id == ^branch_id, select: f.id) |> MapSet.new()

    branch = Repo.get!(Branch, branch_id)

    if branch.parent_id == nil do
      defined_here
    else
      parent_funcsets = collect_branch_funcsets(branch.parent_id)
      whitelist = Repo.all(from w in BranchWhitelist, where: w.branch_id == ^branch_id, select: w.funcset_id) |> MapSet.new()

      from_parent = if branch.propagate_parent do
        parent_funcsets
      else
        MapSet.intersection(parent_funcsets, whitelist)
      end

      MapSet.union(defined_here, from_parent)
    end
  end

  # ── User funcsets (RBAC resolution) ──

  def user_branches(userid) do
    safe_id = safe_value!(userid)
    Repo.all(from e in Employee, where: e.person_id == ^safe_id, select: e.branch_id, distinct: true)
  end

  def user_positions(userid) do
    safe_id = safe_value!(userid)
    Repo.all(from e in Employee, where: e.person_id == ^safe_id, select: e.position)
  end

  defp user_funcsets(userid) do
    safe_id = safe_value!(userid)
    case Repo.one(from e in Employee, where: e.person_id == ^safe_id, limit: 1) do
      nil -> []
      emp ->
        branch_id = emp.branch_id
        whitelist = collect_branch_funcsets(branch_id)
        role_node = find_role_in_ancestors(emp.position, branch_id)
        if role_node == nil do
          Logger.error("Position '#{emp.position}' used in branch '#{branch_id}' without role definition")
          []
        else
          role_funcsets = Repo.all(from rf in RoleFuncset, where: rf.role_id == ^role_node.id, select: rf.funcset_id) |> MapSet.new()
          MapSet.intersection(whitelist, role_funcsets) |> MapSet.to_list()
        end
    end
  end

  # ── Functions catalogue ──

  @func_props %{
    "id" => :id,
    "name" => :name,
    "title" => :title,
    "description" => :description,
    "callpath" => :call_url,
    "method" => :call_method,
    "contenttype" => :call_content_type
  }

  def list_functions(prop) do
    case Map.get(@func_props, prop) do
      nil -> err("WRONG-FORMAT", "Property #{inspect(prop)} is unknown")
      field ->
        values = Repo.all(from f in FunctionDef, select: ^[field])
          |> Enum.map(fn row ->
            val = Map.get(row, field, "")
            if prop == "callpath" do
              val |> to_string() |> String.split("?") |> hd()
            else
              val
            end
          end)
          |> Enum.reject(& &1 in [nil, ""])
          |> Enum.uniq()
          |> Enum.sort()
        ok(%{"property" => prop, "values" => values})
    end
  end

  def review_functions(props, function_id \\ nil) do
    prop_list = String.split(props, ",")

    if !Enum.all?(prop_list, &Map.has_key?(@func_props, &1)) do
      err("WRONG-FORMAT", "One or more properties are unknown")
    else
      q = if function_id != nil do
        safe_fid = safe_value!(function_id)
        from f in FunctionDef, where: f.id == ^safe_fid
      else
        from f in FunctionDef
      end

      funcs = Repo.all(q)

      if funcs == [] and function_id != nil do
        err("FUNCTION-UNKNOWN", "Function #{function_id} is not described in catalogue")
      else
        extract = fn func ->
          Enum.reduce(prop_list, %{}, fn p, acc ->
            field = Map.get(@func_props, p)
            val = Map.get(func, field, "")
            val = if p == "callpath", do: val |> to_string() |> String.split("?") |> hd(), else: val
            if val not in [nil, ""], do: Map.put(acc, p, val), else: acc
          end)
        end

        if function_id == nil do
          ok(%{"functions" => Enum.map(funcs, extract)})
        else
          ok(%{"props" => extract.(hd(funcs)), "function_id" => function_id})
        end
      end
    end
  end

  def get_function_def(func_id, header \\ "") do
    safe_id = safe_value!(func_id)
    case Repo.get(FunctionDef, safe_id) do
      nil -> err("FUNCTION-UNKNOWN", "Function '#{func_id}' is unknown")
      func -> ok(%{"definition" => header <> func.xml_definition})
    end
  end

  def post_function_def(xml_text) do
    # Parse minimal info from XML text
    case parse_function_xml(xml_text) do
      {:error, reason} ->
        err("WRONG-DATA", "Cannot parse function description: #{reason}")
      {:ok, attrs} ->
        func_id = attrs[:id]
        if func_id == nil do
          err("WRONG-DATA", "Function does not have 'id' attribute")
        else
          case Repo.get(FunctionDef, func_id) do
            nil ->
              %FunctionDef{} |> FunctionDef.changeset(Map.put(attrs, :xml_definition, xml_text)) |> Repo.insert!()
              ok(%{"function_id" => func_id, "status" => "APPENDED"})
            existing ->
              old_def = existing.xml_definition
              existing |> FunctionDef.changeset(Map.merge(attrs, %{xml_definition: xml_text})) |> Repo.update!()
              ok(%{"function_id" => func_id, "status" => "REPLACED", "old_definition" => old_def})
          end
        end
    end
  end

  def delete_function_def(nil), do: err("WRONG-FORMAT", "Function ID is required")
  def delete_function_def(func_id) do
    safe_id = safe_value!(func_id)
    case Repo.get(FunctionDef, safe_id) do
      nil -> err("FUNCTION-UNKNOWN", "Function '#{func_id}' is unknown")
      func ->
        old_def = func.xml_definition
        Repo.delete!(func)
        ok(%{"function_id" => func_id, "status" => "DELETED", "old_definition" => old_def})
    end
  end

  def modify_func_tagset(func_id, method, tagset, read_only \\ false) do
    cond do
      any_empty?([func_id, method]) ->
        err("WRONG-FORMAT", "Required parameter not given")
      true ->
        safe_id = safe_value!(func_id)
        case Repo.get(FunctionDef, safe_id) do
          nil -> err("FUNCTION-UNKNOWN", "Function #{inspect(func_id)} is unknown")
          func ->
            old_tagset = (func.tags || "") |> String.split(",") |> MapSet.new()
            new_tagset = MapSet.new(tagset)

            result = case method do
              "SET" when not read_only -> new_tagset
              "OR" -> MapSet.union(new_tagset, old_tagset)
              "AND" -> MapSet.intersection(new_tagset, old_tagset)
              "MINUS" -> MapSet.difference(old_tagset, new_tagset)
              _ -> :invalid
            end

            if result == :invalid do
              err("WRONG-FORMAT", "Method #{inspect(method)} is unapplicable", %{"wrong_value" => method})
            else
              tag_str = result |> MapSet.to_list() |> Enum.join(",")
              unless read_only do
                FunctionDef.changeset(func, %{tags: tag_str}) |> Repo.update!()
              end
              ok(%{"tagset" => tag_str})
            end
        end
    end
  end

  # ── Agents ──

  def get_agents do
    Repo.all(from a in Agent, select: a.agent_id, order_by: a.agent_id)
  end

  def get_sub_branches_of_agent(agent_id) do
    case Repo.get(Agent, agent_id) do
      nil -> []
      agent ->
        branch_id = agent.branch_id
        [branch_id | get_all_descendant_ids(branch_id)]
    end
  end

  def register_agent_in_branch(branch_id, agent_id, opts \\ []) do
    move = Keyword.get(opts, :move, false)
    descr = Keyword.get(opts, :descr, "")
    location = Keyword.get(opts, :location, "")
    tags = Keyword.get(opts, :tags, "")
    extra_xml = Keyword.get(opts, :extra_xml, "")

    # Resolve *ROOT*
    branch_id = if branch_id == "*ROOT*" do
      case Repo.one(from b in Branch, where: is_nil(b.parent_id), limit: 1, select: b.id) do
        nil -> branch_id
        root_id -> root_id
      end
    else
      branch_id
    end

    current = Repo.get(Agent, agent_id)

    if !move do
      validation = validate_extra_xml(extra_xml)
      case {current, validation} do
        {%{branch_id: _}, _} ->
          err("ALREADY-EXISTS", "Agent #{inspect(agent_id)} already registered in branch #{inspect(current.branch_id)}", %{"bad_value" => agent_id})
        {_, {:error, error}} ->
          err("WRONG-FORMAT", "extraxml field does not fit into XML format, details: #{inspect(error)}")
        {_, :ok} ->
          insert_agent(agent_id, branch_id, descr, location, tags, extra_xml)
      end
    else
      if current == nil do
        err("AGENT-UNKNOWN", "Agent #{inspect(agent_id)} is never registered", %{"bad_value" => agent_id})
      else
        curr_descendants = [current.branch_id | get_all_descendant_ids(current.branch_id)]
        if branch_id not in curr_descendants do
          err("NOT-IN-SET", "Branch #{inspect(branch_id)} is not a subsidiary of branch #{inspect(current.branch_id)}", %{"bad_value" => branch_id})
        else
          unregister_agent(agent_id)
          insert_agent(agent_id, branch_id, descr, location, tags, extra_xml)
        end
      end
    end
  end

  defp insert_agent(agent_id, branch_id, descr, location, tags, extra_xml) do
    Repo.insert!(%Agent{agent_id: agent_id, branch_id: branch_id, description: descr, location: location, extra_xml: extra_xml})
    tag_list = tags |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(& &1 == "")
    Enum.each(tag_list, fn t ->
      Repo.insert!(%AgentTag{agent_id: agent_id, tag: t})
    end)
    ok()
  end

  defp validate_extra_xml(extra_xml) when is_binary(extra_xml) do
    try do
      :xmerl_scan.string(to_charlist("<extra>#{extra_xml}</extra>"))
      :ok
    rescue
      exception ->
        {:error, exception}
    end
  end

  defp validate_extra_xml(_), do: {:error, :invalid_xml}

  def unregister_agent(agent_id) do
    case Repo.get(Agent, agent_id) do
      nil -> err("AGENT-UNKNOWN", "Agent #{inspect(agent_id)} is never registered", %{"bad_value" => agent_id})
      agent ->
        Repo.delete_all(from t in AgentTag, where: t.agent_id == ^agent_id)
        Repo.delete!(agent)
        ok()
    end
  end

  def agent_details_xml(agent_id) do
    case get_agent_dict(agent_id) do
      nil -> err("AGENT-UNKNOWN", "Agent #{inspect(agent_id)} is never registered", %{"bad_value" => agent_id})
      agdict ->
        tags_xml = Enum.map(agdict["tags"], fn t -> "  <tag>#{escape_xml(t)}</tag>" end) |> Enum.join("\n")
        xml = """
        <aginfo>
          <descr>#{escape_xml(agdict["descr"])}</descr>
          <location>#{escape_xml(agdict["location"])}</location>
          <extra>#{escape_xml(agdict["extra"])}</extra>
        #{tags_xml}
        </aginfo>
        """
        ok(%{"details" => xml})
    end
  end

  def agent_details_json(agent_id) do
    case get_agent_dict(agent_id) do
      nil -> err("AGENT-UNKNOWN", "Agent #{inspect(agent_id)} is never registered", %{"bad_value" => agent_id})
      agdict ->
        ok(%{"details" => %{
          "descr" => agdict["descr"],
          "location" => agdict["location"],
          "tags" => Enum.join(agdict["tags"], ","),
          "extra" => agdict["extra"]
        }})
    end
  end

  def list_agents(branch_id, with_subsids, with_locs) do
    branch_ids = if branch_id == "*ALL*" do
      list_branches()
    else
      if with_subsids do
        [branch_id | get_all_descendant_ids(branch_id)]
      else
        [branch_id]
      end
    end

    agents = Repo.all(from a in Agent, where: a.branch_id in ^branch_ids, select: {a.agent_id, a.branch_id})

    report = if with_locs do
      Enum.map(agents, fn {aid, bid} -> %{"agent" => aid, "branch" => bid} end)
    else
      Enum.map(agents, fn {aid, _bid} -> aid end)
    end

    ok(%{"report" => report})
  end

  defp list_agents_report(branch_id, with_subsids, with_locs) do
    case list_agents(branch_id, with_subsids, with_locs) do
      %{"report" => r} -> r
      _ -> []
    end
  end

  defp get_agent_dict(agent_id) do
    case Repo.get(Agent, agent_id) do
      nil -> nil
      agent ->
        tags = Repo.all(from t in AgentTag, where: t.agent_id == ^agent_id, select: t.tag)
        %{
          "agent_id" => agent.agent_id,
          "branch" => agent.branch_id,
          "descr" => agent.description || "",
          "location" => agent.location || "",
          "extra" => agent.extra_xml || "",
          "tags" => tags
        }
    end
  end

  # ── Operator authority checks ──

  defp check_operator_branch_authority(operator, target_branch) do
    op_branches = user_branches(operator)

    if op_branches == [] do
      {:error, err("FORBIDDEN-FOR-OP", "Operator #{inspect(operator)} is nowhere employed")}
    else
      op_branch = hd(op_branches)
      descendants = [op_branch | get_all_descendant_ids(op_branch)]
      if target_branch in descendants, do: :ok,
      else: {:error, err("FORBIDDEN-FOR-OP", "Branch #{inspect(target_branch)} is not accountable to operator #{inspect(operator)}")}
    end
  end

  defp check_operator_employee_authority(operator, userid) do
    op_branches = user_branches(operator)

    if op_branches == [] do
      {:error, err("FORBIDDEN-FOR-OP", "Operator #{inspect(operator)} is nowhere employed")}
    else
      op_branch = hd(op_branches)
      descendants = [op_branch | get_all_descendant_ids(op_branch)]
      emp_branch = user_branches(userid)
      if emp_branch != [] and hd(emp_branch) in descendants, do: :ok,
      else: {:error, err("FORBIDDEN-FOR-OP", "User #{inspect(userid)} is not accountable to operator #{inspect(operator)}")}
    end
  end

  # ── Branch hierarchy helpers ──

  defp branch_exists?(nil), do: false
  defp branch_exists?(""), do: false
  defp branch_exists?(id), do: Repo.get(Branch, id) != nil

  defp get_ancestor_ids(branch_id) do
    do_get_ancestors(branch_id, [])
  end

  defp do_get_ancestors(branch_id, acc) do
    case Repo.get(Branch, branch_id) do
      nil -> acc
      %{parent_id: nil} -> acc
      %{parent_id: pid} -> do_get_ancestors(pid, acc ++ [pid])
    end
  end

  defp get_all_descendant_ids(branch_id) do
    children = Repo.all(from b in Branch, where: b.parent_id == ^branch_id, select: b.id)
    children ++ Enum.flat_map(children, &get_all_descendant_ids/1)
  end

  defp get_direct_children_ids(branch_id) do
    Repo.all(from b in Branch, where: b.parent_id == ^branch_id, select: b.id)
  end

  # ── Helpers ──

  defp any_nil?(list), do: Enum.any?(list, &is_nil/1)
  defp any_empty?(list), do: Enum.any?(list, & &1 in [nil, ""])

  defp default_session_max, do: Application.get_env(:aac, :session_max_default, 60)

  defp parse_int(nil), do: nil
  defp parse_int(s) when is_integer(s), do: s
  defp parse_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_float(nil), do: 0.0
  defp parse_float(s) when is_float(s), do: s
  defp parse_float(s) when is_integer(s), do: s * 1.0
  defp parse_float(s) when is_binary(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp validate_not_empty(val, _name) when val not in [nil, ""], do: :ok
  defp validate_not_empty(_val, name), do: {:error, err("WRONG-FORMAT", "Required #{name} is not given")}

  defp escape_xml(s) when is_binary(s) do
    s
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
  defp escape_xml(nil), do: ""

  defp parse_function_xml(xml_text) do
    try do
      {xml_doc, _} = :xmerl_scan.string(to_charlist(xml_text))
      root = xmlDocument(xml_doc, :root)
      {:ok, %{
        id: xpath_attr_value(root, "id"),
        name: xpath_text(root, "string(@name)") || "",
        title: xpath_text(root, "string(@title)") || "",
        description: xpath_text(root, "string(@descr)") || "",
        tags: xpath_text(root, "string(@tags)") || "",
        call_method: xpath_text(root, "string(call/@method)") || "",
        call_url: xpath_text(root, "string(call/url[1]/text()[1])") || "",
        call_content_type: xpath_text(root, "string(call/body/@content-type)") || ""
      }}
    rescue
      e -> {:error, inspect(e)}
    end
  end

  defp xpath_text(node, xpath) do
    case :xmerl_xpath.string(to_charlist(xpath), node) do
      nil -> ""
      value when is_list(value) -> List.to_string(value)
      value -> to_string(value)
    end
  end

  defp xpath_attr_value(node, attr_name) do
    attr_name = to_string(attr_name)
    xmlElement(node, :attributes)
    |> Enum.find_value(fn attr ->
      if to_string(xmlAttribute(attr, :name)) == attr_name do
        xmlAttribute(attr, :value) |> to_string()
      end
    end)
  end
end
