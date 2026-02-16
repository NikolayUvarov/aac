defmodule AacWeb.Router do
  use Phoenix.Router
  import Plug.Conn
  import Phoenix.Controller

  pipeline :api do
    plug :accepts, ["json", "xml"]
    plug :fetch_query_params
  end

  # Root redirect
  scope "/", AacWeb do
    get "/", RedirectController, :index
    get "/index.html", RedirectController, :index
    get "/aac", RedirectController, :index
    get "/aac/", RedirectController, :index
    get "/aac/static/index.html", RedirectController, :index
  end

  scope "/aac", AacWeb do
    pipe_through :api

    # Authentication
    post "/authentificate", AuthController, :authorize
    get "/authentificate", AuthController, :authorize
    post "/authorize", AuthController, :authorize
    get "/authorize", AuthController, :authorize
    get "/user/details", AuthController, :user_details

    # Users
    post "/user/create", UserController, :create
    get "/user/create", UserController, :create
    post "/user/change", UserController, :change
    get "/user/change", UserController, :change
    post "/user/delete", UserController, :delete
    get "/user/delete", UserController, :delete
    get "/users/list", UserController, :list

    # Functions catalogue
    get "/functions/list", FunctionController, :list
    get "/function/review", FunctionController, :review
    get "/functions/review", FunctionController, :review_all
    get "/function/info", FunctionController, :info
    post "/function/delete", FunctionController, :delete
    get "/function/delete", FunctionController, :delete
    post "/function/upload/xmldescr", FunctionController, :upload_xml_descr
    get "/function/upload/xmldescr", FunctionController, :upload_xml_descr
    post "/function/upload/xmlfile", FunctionController, :upload_xml_file
    get "/function/upload/xmlfile", FunctionController, :upload_xml_file
    post "/function/tagset/modify", FunctionController, :tagset_modify
    get "/function/tagset/test", FunctionController, :tagset_test

    # Funcsets
    get "/funcsets", FuncsetController, :index
    post "/funcset/create", FuncsetController, :create
    get "/funcset/create", FuncsetController, :create
    post "/funcset/delete", FuncsetController, :delete
    get "/funcset/delete", FuncsetController, :delete
    get "/funcset/details", FuncsetController, :details
    post "/funcset/function/add", FuncsetController, :func_add
    get "/funcset/function/add", FuncsetController, :func_add
    post "/funcset/function/remove", FuncsetController, :func_remove
    get "/funcset/function/remove", FuncsetController, :func_remove

    # Roles
    get "/role/funcsets", RoleController, :funcsets
    post "/role/funcset/add", RoleController, :funcset_add
    get "/role/funcset/add", RoleController, :funcset_add
    post "/role/funcset/remove", RoleController, :funcset_remove
    get "/role/funcset/remove", RoleController, :funcset_remove

    # Branches
    get "/branches", BranchController, :index
    get "/branch/subbranches", BranchController, :subbranches
    post "/branch/subbranch/add", BranchController, :subbranch_add
    get "/branch/subbranch/add", BranchController, :subbranch_add
    post "/branch/delete", BranchController, :delete
    get "/branch/delete", BranchController, :delete
    get "/branch/fswhitelist/get", BranchController, :fswl_get
    post "/branch/fswhitelist/set", BranchController, :fswl_set
    get "/branch/fswhitelist/set", BranchController, :fswl_set
    get "/branch/roles/list", BranchController, :roles_list
    post "/branch/role/create", BranchController, :role_create
    get "/branch/role/create", BranchController, :role_create
    post "/branch/role/delete", BranchController, :role_delete
    get "/branch/role/delete", BranchController, :role_delete
    get "/branch/employees/list", BranchController, :employees_list

    # HR / Positions
    get "/hr/branch/positions", EmployeeController, :positions
    post "/hr/branch/position/create", EmployeeController, :position_create
    get "/hr/branch/position/create", EmployeeController, :position_create
    post "/hr/branch/position/delete", EmployeeController, :position_delete
    get "/hr/branch/position/delete", EmployeeController, :position_delete
    post "/hr/hire", EmployeeController, :hire
    get "/hr/hire", EmployeeController, :hire
    post "/hr/fire", EmployeeController, :fire
    get "/hr/fire", EmployeeController, :fire
    get "/positions", EmployeeController, :get_positions

    # Employee queries
    get "/emp/subbranches/list", EmployeeController, :subbranches_list
    get "/emp/funcsets/list", EmployeeController, :funcsets_list
    get "/emp/functions/list", EmployeeController, :functions_list
    get "/emp/functions/review", EmployeeController, :functions_review

    # Agents
    post "/agent/register", AgentController, :register
    get "/agent/register", AgentController, :register
    post "/agent/movedown", AgentController, :movedown
    get "/agent/movedown", AgentController, :movedown
    post "/agent/unregister", AgentController, :unregister
    get "/agent/unregister", AgentController, :unregister
    get "/agent/details/xml", AgentController, :details_xml
    get "/agent/details/json", AgentController, :details_json
    get "/agents/list", AgentController, :list

    # Test runner
    get "/testrunner/states", TestRunnerController, :states
  end
end
