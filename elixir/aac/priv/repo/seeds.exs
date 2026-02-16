# Script for populating the database with seed data matching the Python AAC system.
# Run with: mix run priv/repo/seeds.exs

alias Aac.Repo
alias Aac.Schema.{User, Branch, BranchWhitelist, Funcset, FuncsetFunction,
                   Role, RoleFuncset, Employee, Agent, AgentTag, FunctionDef}

IO.puts("Seeding AAC database...")

# ── Helper ──

defmodule Seeds do
  def insert!(schema, attrs) do
    struct(schema, attrs) |> Aac.Repo.insert!(on_conflict: :nothing)
  end
end

# ══════════════════════════════════════════════════════════════════════
# BRANCHES (organizational hierarchy from universe.xml)
# ══════════════════════════════════════════════════════════════════════

branches = [
  %{id: "top level administration", parent_id: nil, propagate_parent: false},
  %{id: "report-branch", parent_id: "top level administration", propagate_parent: false},
  %{id: "report-branch-DEF", parent_id: "report-branch", propagate_parent: false},
  %{id: "report-branch-client1", parent_id: "report-branch", propagate_parent: false},
  %{id: "Bank1", parent_id: "top level administration", propagate_parent: false},
  %{id: "Bank1|Office1", parent_id: "Bank1", propagate_parent: true},
  %{id: "Bank2", parent_id: "top level administration", propagate_parent: false},
  %{id: "IndentTest1", parent_id: "top level administration", propagate_parent: false},
  %{id: "IndentTest2", parent_id: "IndentTest1", propagate_parent: false},
]

for b <- branches do
  Seeds.insert!(Branch, b)
end

IO.puts("  Branches: #{length(branches)}")

# ══════════════════════════════════════════════════════════════════════
# BRANCH WHITELISTS
# ══════════════════════════════════════════════════════════════════════

whitelists = [
  # report-branch
  {"report-branch", "fullUserFuncs"},
  {"report-branch", "employementFuncs"},
  # report-branch-DEF
  {"report-branch-DEF", "report_common_funcs"},
  {"report-branch-DEF", "report_views-def"},
  # report-branch-client1
  {"report-branch-client1", "report_common_funcs"},
  {"report-branch-client1", "report_views-client1"},
  # Bank1
  {"Bank1", "agentFuncs"},
  {"Bank1", "limUserFuncs"},
  {"Bank1", "employementFuncs"},
  # Bank2
  {"Bank2", "agentFuncs"},
  {"Bank2", "employementFuncs"},
  {"Bank2", "limUserFuncs"},
  {"Bank2", "report_common_funcs"},
]

for {bid, fsid} <- whitelists do
  Seeds.insert!(BranchWhitelist, %{branch_id: bid, funcset_id: fsid})
end

IO.puts("  Whitelist entries: #{length(whitelists)}")

# ══════════════════════════════════════════════════════════════════════
# FUNCSETS (function sets defined in branches)
# ══════════════════════════════════════════════════════════════════════

funcsets = [
  # top level administration
  %{id: "agentFuncs", name: "Agents handling", branch_id: "top level administration"},
  %{id: "employementFuncs", name: "Employement", branch_id: "top level administration"},
  %{id: "fullUserFuncs", name: "Full user management", branch_id: "top level administration"},
  %{id: "limUserFuncs", name: "Limited user management", branch_id: "top level administration"},
  %{id: "Tests", name: "Tests", branch_id: "top level administration"},
  # report-branch
  %{id: "report_common_funcs", name: "Report Common Functions", branch_id: "report-branch"},
  %{id: "report_views-def", name: "Default Report Views", branch_id: "report-branch"},
  %{id: "report_views-client1", name: "Report Views for Client 1", branch_id: "report-branch"},
  # Bank1
  %{id: "bank1ceoFuncs", name: "Bank1 CEO functions", branch_id: "Bank1"},
]

for fs <- funcsets do
  Seeds.insert!(Funcset, fs)
end

IO.puts("  Funcsets: #{length(funcsets)}")

# ══════════════════════════════════════════════════════════════════════
# FUNCSET FUNCTIONS
# ══════════════════════════════════════════════════════════════════════

funcset_funcs = [
  {"agentFuncs", "agadm:createAgent"},
  {"agentFuncs", "agadm:deleteAgent"},
  {"employementFuncs", "eadm:employeeHire"},
  {"employementFuncs", "eadm:employeeFire"},
  {"fullUserFuncs", "uadm:createUser"},
  {"fullUserFuncs", "uadm:deleteUser"},
  {"limUserFuncs", "uadm:createUser"},
  {"Tests", "test:states"},
  # report funcs
  {"report_common_funcs", "report:data-sources-list"},
  {"report_views-def", "report:def:apiview"},
  {"report_views-def", "report:def:mapview"},
  {"report_views-def", "report:def:overview"},
  {"report_views-def", "report:def:overview-summ"},
  {"report_views-def", "report:def:overview-summ-long"},
  {"report_views-client1", "report:cl1:apiview"},
  {"report_views-client1", "report:cl1:mapview"},
  {"report_views-client1", "report:cl1:overview"},
  {"report_views-client1", "report:cl1:overview-summ"},
  {"report_views-client1", "report:cl1:overview-summ-long"},
  # Bank1 CEO funcs
  {"bank1ceoFuncs", "createUser"},
  {"bank1ceoFuncs", "employeeHire"},
  {"bank1ceoFuncs", "employeeFire"},
]

for {fsid, fid} <- funcset_funcs do
  Seeds.insert!(FuncsetFunction, %{funcset_id: fsid, function_id: fid})
end

IO.puts("  Funcset functions: #{length(funcset_funcs)}")

# ══════════════════════════════════════════════════════════════════════
# ROLES
# ══════════════════════════════════════════════════════════════════════

roles_data = [
  # top level administration
  {"top level administration", "CEO", ["Tests", "limUserFuncs", "employementFuncs"]},
  {"top level administration", "HR", ["Tests", "limUserFuncs"]},
  {"top level administration", "atm-support", ["Tests", "agentFuncs"]},
  {"top level administration", "top-admin-assistant", ["Tests", "fullUserFuncs", "branchFuncs", "employementFuncs", "agentFuncs"]},
  {"top level administration", "top-admin-great-magister", ["Tests", "fullUserFuncs", "superFuncs", "branchFuncs", "employementFuncs", "agentFuncs"]},
  # report-branch
  {"report-branch", "report-admin", ["employementFuncs", "fullUserFuncs", "report_common_funcs"]},
  {"report-branch", "report-user", ["report_common_funcs", "report_views-def", "report_views-client1"]},
  # Bank1
  {"Bank1", "CEO", ["bank1ceoFuncs", "employementFuncs"]},
  {"Bank1", "HR", ["limUserFuncs"]},
  {"Bank1", "office_head", ["agentFuncs"]},
]

for {bid, name, duty_list} <- roles_data do
  {:ok, role} = Repo.insert(%Role{name: name, branch_id: bid}, on_conflict: :nothing, conflict_target: [:name, :branch_id])
  if role.id do
    for d <- duty_list do
      Seeds.insert!(RoleFuncset, %{role_id: role.id, funcset_id: d})
    end
  end
end

IO.puts("  Roles: #{length(roles_data)}")

# ══════════════════════════════════════════════════════════════════════
# USERS (people register from universe.xml)
# ══════════════════════════════════════════════════════════════════════

users = [
  %{id: "Ivanov", secret: "b6f5d8f4094923899760aeb1e2a06bef49922e6e1767a7ca0c9063324c9a05a6", psw_changed_at: 1676053730, failures: 0, last_auth_success: 1684624780, last_error: 1676322691, expire_at: 1707589730},
  %{id: "Petrov", secret: "c18b0fd384e1df921f75ec456718423b31d63ad5133a2ec14a3590ff9d49278b", psw_changed_at: 1661849127, failures: 0, last_error: 1661881859, last_auth_success: 1678173950},
  %{id: "Sidorov", secret: "4c28a43d9a9c1802dcc1b54746f042f86c5de2e98ebf26f134e4b5a142ffaf12", psw_changed_at: 1661849156, failures: 0, last_error: 1667561734, last_auth_success: 1676411865},
  %{id: "Jack", secret: "b363d9ff4d75b36875a45369f99a64e2b95901979fc617a73f0d619dfcebf3fa", psw_changed_at: 1661849211, failures: 0},
  %{id: "Ncr", secret: "53a1e06788d225c05e2b6a2cfee89dbcee900e1df19a592dc75cd8c25c56fa58", psw_changed_at: 1661849230, failures: 0},
  %{id: "John Snow", secret: "5372d9e09fc73f7b93ac02b4bbaa050f087b60f0de9d5f012b6700a75cc9a020", psw_changed_at: 1661849260, failures: 0},
  %{id: "Targarien", secret: "4ca9a23f1a81d6d31c6d434e9a62ac445bd87a1c4ae1ad7f496fd977954db955", psw_changed_at: 1661955906, failures: 3, last_auth_success: 1661955921, expire_at: 1693491906, last_error: 1676132971},
  %{id: "Lebovski", secret: "5481571f15561de4aefb06b45863ee97488b8a2bbd085f9e6f67a8a448f2717a", psw_changed_at: 1661849313, failures: 0, last_auth_success: 1668290517},
  %{id: "NewOne", secret: "54a8091b4aa7cf4f6f42aed3adbdf9b47f724d1f5bf00b390f67bbc89f0c9e3d", psw_changed_at: 1661849336, failures: 0},
  %{id: "MiniMe", secret: "3821297e97ee1ed020bf671d78ab669efb9239a7f8f108b487fa07bfb26ada8e", psw_changed_at: 1661849349, failures: 0},
  %{id: "Johnson", secret: "a3f9caa290c916b021cf640817c3791c50c80b92ab1bb99a3f1d0fd71ea68852", psw_changed_at: 1668290623, failures: 0, expire_at: 1699826623, last_auth_success: 1668290638},
  %{id: "Ivan", secret: "04b823c6148854d37bfb8a9546b74cfb207e8e55dc62b46034f1fd85ef0cdff4", psw_changed_at: 1663756431, failures: 0, last_auth_success: 1663521947, expire_at: 1695292431},
  %{id: "Test", secret: "fcd972b47018ed07ef0e700aa25ba7195dd57f306dc302e2d1ba6aabbbc415f2", psw_changed_at: 1665249689, failures: 0, expire_at: 1680801689},
  %{id: "admin", secret: "c4a3bea5d95492c49eb60f858ccb9cc0284ff4bea008013c6f07e2e61a95b315", psw_changed_at: 1667469052, failures: 0, expire_at: 1683021052},
  %{id: "admin22", secret: "f719c2ed8f1d9edcbc840094fa8d7282c83fc233cb66fc59ef96bd1875f3e468", psw_changed_at: 1680724483, failures: 0, readable_name: "Ulovka 22", session_max: 60, expire_at: 1712260483},
  %{id: "report-admin", secret: "25def6da3f9de1b878900dbf6cb044154992311e0bf0cbe0efe18ab7bcd98200", psw_changed_at: 1667485686, failures: 0, last_error: 1667625517, last_auth_success: 1667660442},
  %{id: "Qwert", secret: "24dafc54ae60f8e62b4dbb7e7f6e021205692ae59123a7c1a8e10d9603750788", psw_changed_at: 1669241413, failures: 0, expire_at: 1700777413, last_error: 1669241400, last_auth_success: 1676132993},
  %{id: "Qwer5", secret: "295502867b71344058d9d8afac33ce6ba47ddf058e20e09cec821e1c3d3a55fa", psw_changed_at: 1668118344, failures: 0},
  %{id: "Wert", secret: "0f6f756a6fc7f492d71154c7a67992174d2b168b87c24a2e902e51b93a8d5e57", psw_changed_at: 1669241472, failures: 0, expire_at: 1700777472, last_auth_success: 1669241485},
  %{id: "Nikonov", secret: "f1659a734694456579568c10c470200906e681794078e0e45efd0e85b9dc35d3", psw_changed_at: 1669241517, failures: 0, expire_at: 1700777517},
  %{id: "BlaBlaCar", secret: "535a3699fc6dccb0ee7ae65095dd9f1dd4090a011332e7cb5a3273f63a97ee9d", psw_changed_at: 1674163661, failures: 0, expire_at: 1689715661},
  %{id: "Kotov", secret: "53fd05622bc49c2dd34f9b1649929113450f3bfcff0c501c7a297936f1a42ade", psw_changed_at: 1676132585, failures: 0, expire_at: 1707668585},
  %{id: "Kots", secret: "3950711fbb7094cd42a5a5e8aae774ab3f0858f3ccd7deb3280dab076540da92", psw_changed_at: 1676479092, failures: 0, readable_name: "Sergey V. Kotov", session_max: 33, created_by: "Ivanov", created_at: 1676470744, expire_at: 1708015092, last_auth_success: 1691148479},
  %{id: "Kobrin", secret: "1827fc86524cc2e784414d7144f28d57abd37f5b55a668cabe9fde37f15ad07e", psw_changed_at: 1678196264, failures: 0, readable_name: "Alexander Kobrin", session_max: 120, created_by: "Kots", created_at: 1678196264, expire_at: 1693748264, last_auth_success: 1678196325},
]

for u <- users do
  Seeds.insert!(User, Map.merge(%{session_max: 60, readable_name: "", created_by: "", created_at: 0}, u))
end

IO.puts("  Users: #{length(users)}")

# ══════════════════════════════════════════════════════════════════════
# EMPLOYEES (positions and assignments)
# ══════════════════════════════════════════════════════════════════════

employees = [
  # top level administration
  %{branch_id: "top level administration", position: "top-admin-great-magister", person_id: "Ivanov", is_head: true},
  %{branch_id: "top level administration", position: "top-admin-assistant", person_id: "NewOne"},
  %{branch_id: "top level administration", position: "top-admin-assistant", person_id: "Kots"},
  # report-branch
  %{branch_id: "report-branch", position: "report-admin", person_id: "report-admin", is_head: true},
  # report-branch-DEF
  %{branch_id: "report-branch-DEF", position: "report-user", person_id: nil},
  # report-branch-client1
  %{branch_id: "report-branch-client1", position: "report-user", person_id: nil},
  %{branch_id: "report-branch-client1", position: "report-admin", person_id: "Nikonov"},
  # Bank1
  %{branch_id: "Bank1", position: "CEO", person_id: nil, is_head: true},
  %{branch_id: "Bank1", position: "HR", person_id: "Targarien"},
  %{branch_id: "Bank1", position: "HR", person_id: "Qwert"},
  %{branch_id: "Bank1", position: "HR", person_id: nil},
  %{branch_id: "Bank1", position: "atm-support", person_id: "Jack"},
  %{branch_id: "Bank1", position: "atm-support", person_id: "MiniMe"},
  %{branch_id: "Bank1", position: "atm-support", person_id: "Test"},
  # Bank1|Office1
  %{branch_id: "Bank1|Office1", position: "office_head", person_id: "Sidorov", is_head: true},
  %{branch_id: "Bank1|Office1", position: "atm-support", person_id: "John Snow"},
  %{branch_id: "Bank1|Office1", position: "atm-support", person_id: "Ivan"},
  %{branch_id: "Bank1|Office1", position: "atm-support", person_id: "Kotov"},
  # Bank2
  %{branch_id: "Bank2", position: "CEO", person_id: "Petrov", is_head: true},
]

for e <- employees do
  Seeds.insert!(Employee, Map.merge(%{is_head: false}, e))
end

IO.puts("  Employees: #{length(employees)}")

# ══════════════════════════════════════════════════════════════════════
# FUNCTION DEFINITIONS (from catalogues.xml)
# ══════════════════════════════════════════════════════════════════════

function_defs = [
  %{id: "report:data-sources-list", name: "", title: "", call_method: "GET", call_url: "/i2/report"},
  %{id: "report:def:apiview", name: "", title: "", call_method: "GET", call_url: "/i2/report/def/apiview.html"},
  %{id: "report:def:mapview", name: "", title: "", call_method: "GET", call_url: "/i2/report/def/mapview.html"},
  %{id: "report:def:overview", name: "", title: "", call_method: "GET", call_url: "/i2/report/def/overview.html"},
  %{id: "report:def:overview-summ", name: "", title: "", call_method: "GET", call_url: "/i2/report/def/overview-sum.html"},
  %{id: "report:def:overview-summ-long", name: "", title: "", call_method: "GET", call_url: "/i2/report/def/overview-sum-long.html"},
  %{id: "report:cl1:apiview", name: "", title: "", call_method: "GET", call_url: "/i2/report/client1/apiview.html"},
  %{id: "report:cl1:mapview", name: "", title: "", call_method: "GET", call_url: "/i2/report/client1/mapview.html"},
  %{id: "report:cl1:overview", name: "", title: "", call_method: "GET", call_url: "/i2/report/client1/overview.html"},
  %{id: "report:cl1:overview-summ", name: "", title: "", call_method: "GET", call_url: "/i2/report/client1/overview-sum.html"},
  %{id: "report:cl1:overview-summ-long", name: "", title: "", call_method: "GET", call_url: "/i2/report/client1/overview-sum-long.html"},
  %{id: "uadm:createUser", name: "Create user", title: "Create user", description: "This function creates a new user", call_method: "POST", call_url: "/aac/user/create", call_content_type: "application/x-www-form-urlencoded",
     xml_definition: ~S(<function id="uadm:createUser" name="Create user" title="Create user" descr="This function creates a new user"><in><str entry="USERNAME" check="^.+$" title="New user ID"/><password entry="PSW" check="^.+$" title="Password for new user"/><sha256 new="SECRET"><concat><insert from="PSW"/><insert from="USERNAME"/></concat></sha256><bool entry="EXPIREABLE" default="yes" title="Password can expire"/><duration entry="LIFETIME" if-yes="EXPIREABLE" default="180" title="Password life time (days)"/><duration entry="SESSMAX" default="120" title="Session duration limit (minutes)"/></in><call method="POST"><url>/aac/user/create</url><body content-type="application/x-www-form-urlencoded">username=&amp;secret=&amp;operator=</body></call><out format="json"><done if="$.result" eq="true" title="Operation done"><timestamp id="CHANGED_TS" select="$.secret_changed" title="Password changed"/></done><failed title="Operation failed"><str id="FAIL_REASON" select="$.reason" title="Failure reason"/></failed></out></function>)},
  %{id: "uadm:deleteUser", name: "Delete user", title: "Delete user", description: "Delete user", call_method: "POST", call_url: "/aac/user/delete", call_content_type: "application/x-www-form-urlencoded",
     xml_definition: ~S(<function id="uadm:deleteUser" name="Delete user" title="Delete user" descr="Delete user"><in><str entry="USERNAME" check="^.+$" name="User name" title="Existing user name"/></in><call method="POST"><url>/aac/user/delete</url></call><out format="json"><done if="$.result" eq="true" title="User deleted"/><failed title="Fail"><str id="FAIL_REASON" select="$.reason"/></failed></out></function>)},
  %{id: "agadm:createAgent", name: "Create agent", title: "Create new agent", description: "Create new agent in the system", call_method: "POST", call_url: "/aac/agent/register", call_content_type: "application/x-www-form-urlencoded",
     xml_definition: ~S(<function id="agadm:createAgent" name="Create agent" title="Create new agent" descr="Create new agent in the system"><in><str entry="BRANCH" check="^.+$" title="Agent branch"/><str entry="AGENTID" check="^.+$" title="New agent ID"/></in><call method="POST"><url>/aac/agent/register</url></call><out format="json"><done if="$.result" eq="true" title="Agent created"/><failed title="Fail"><str id="FAIL_REASON" select="$.reason"/></failed></out></function>)},
  %{id: "agadm:deleteAgent", name: "Delete agent", title: "Delete agent", description: "Delete agent from the system", call_method: "POST", call_url: "/aac/agent/unregister", call_content_type: "application/x-www-form-urlencoded",
     xml_definition: ~S(<function id="agadm:deleteAgent" name="Delete agent" title="Delete agent" descr="Delete agent from the system"><in><str entry="AGENTID" check="^.+$" title="Agent ID"/></in><call method="POST"><url>/aac/agent/unregister</url></call><out format="json"><done if="$.result" eq="true" title="Agent deleted"/><failed title="Fail"><str id="FAIL_REASON" select="$.reason"/></failed></out></function>)},
  %{id: "eadm:employeeHire", name: "Hire employee", title: "Hire employee", description: "Hire employee", call_method: "POST", call_url: "/aac/hr/hire", call_content_type: "application/x-www-form-urlencoded",
     xml_definition: ~S(<function id="eadm:employeeHire" name="Hire employee" title="Hire employee" descr="Hire employee"><in><str entry="USERNAME" check="^.+$" title="User name"/><str entry="BRANCH" check="^.+$" title="Branch"/><str entry="POSITION" check="^.+$" title="Position"/></in><call method="POST"><url>/aac/hr/hire</url></call><out format="json"><done if="$.result" eq="true" title="Employee hired"/><failed title="Fail"><str id="FAIL_REASON" select="$.reason"/></failed></out></function>)},
  %{id: "eadm:employeeFire", name: "Fire employee", title: "Fire employee", description: "Fire employee", call_method: "POST", call_url: "/aac/hr/fire", call_content_type: "application/x-www-form-urlencoded",
     xml_definition: ~S(<function id="eadm:employeeFire" name="Fire employee" title="Fire employee" descr="Fire employee"><in><str entry="USERNAME" check="^.+$" title="User name"/></in><call method="POST"><url>/aac/hr/fire</url></call><out format="json"><done if="$.result" eq="true" title="Employee fired"/><failed title="Fail"><str id="FAIL_REASON" select="$.reason"/></failed></out></function>)},
  %{id: "test:states", name: "States Test", title: "States Test", description: "Simulation of a long running function with intermediate states", tags: "test3,test2,test4,test1", call_method: "GET", call_url: "/aac/testrunner/states",
     xml_definition: ~S(<function id="test:states" name="States Test" title="States Test" descr="Simulation of a long running function" tags="test3,test2,test4,test1"><in><duration entry="EACHDUR" default="10" title="Each step duration (sec)"/><str entry="STATES" title="Steps comma separated" default="STATE1,STATE2,STATE3"/><str entry="FINAL" title="Final message" default="Hello, world!"/><str entry="AGENT" title="Agent ID" default="---"/></in><call method="GET"><url>/aac/testrunner/states</url></call><out format="json"><done if="$.state" eq="done" title="Finished"><str id="TASK_ID" select="$.task_id"/></done><failed title="Fail"><str id="FAIL_REASON" select="$.reason"/></failed></out></function>)},
  %{id: "agent:screenshot", name: "Screenshot", title: "Screen shot", description: "Shot of screens", call_method: "GET", call_url: "/sch/screenshot"},
  %{id: "agent:getfile", name: "Getfile", title: "Get file", description: "Get arbitrary file from remote agent", call_method: "GET", call_url: "/sch/getfile"},
]

for fd <- function_defs do
  Seeds.insert!(FunctionDef, Map.merge(%{xml_definition: "", description: "", tags: "", call_content_type: ""}, fd))
end

IO.puts("  Function definitions: #{length(function_defs)}")

# ══════════════════════════════════════════════════════════════════════
# USER CHANGE HISTORY
# ══════════════════════════════════════════════════════════════════════

alias Aac.Schema.UserChange

changes = [
  %{user_id: "admin22", changed_by: "Ivanov", changed_at: 1680724483},
  %{user_id: "Kots", changed_by: "Petrov", changed_at: 1676473893},
  %{user_id: "Kots", changed_by: "Petrov", changed_at: 1676473903},
  %{user_id: "Kots", changed_by: "Ivanov", changed_at: 1676479092},
]

for c <- changes do
  Seeds.insert!(UserChange, c)
end

IO.puts("  User changes: #{length(changes)}")

IO.puts("\nSeeding complete!")
