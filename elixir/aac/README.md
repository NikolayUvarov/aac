# AAC - Authenticate, Authorize, Configure (Elixir)

Elixir/Phoenix port of the Python AAC system - a hierarchical RBAC (Role-Based Access Control) system.

## Architecture

| Python (original)         | Elixir (this port)                    |
|---------------------------|---------------------------------------|
| Quart (async Flask)       | Phoenix Framework                     |
| XML files (lxml/XPath)    | SQLite via Ecto                       |
| SQLite (agents only)      | SQLite via Ecto (all data)            |
| YAML config               | Elixir config (config/*.exs)          |
| Jinja2 templates          | JSON API only (no HTML forms)         |
| testRunner (asyncio)      | TestRunner GenServer                  |

## Key improvements over Python version

- **Proper database**: All data in SQLite via Ecto (no XML file corruption risk)
- **Concurrency safe**: Ecto transactions instead of file-based "castling"
- **No XPath injection**: Parameterized Ecto queries throughout
- **Supervisor tree**: Automatic restart on failures
- **Structured schema**: Proper foreign keys and constraints

## Prerequisites

- Elixir >= 1.14
- Erlang/OTP >= 25

### Install Elixir (Ubuntu/Debian)

```bash
sudo apt-get install elixir erlang
```

### Install Elixir (macOS)

```bash
brew install elixir
```

## Setup

```bash
cd elixir/aac

# Install dependencies
mix deps.get

# Create database and run migrations
mix ecto.setup

# This also runs seeds.exs which loads all initial data
# (users, branches, roles, funcsets, employees, function definitions)
```

## Running

```bash
# Development mode (port 5001)
mix phx.server

# Or in interactive shell
iex -S mix phx.server
```

Server starts on http://localhost:5001

## API Endpoints

All endpoints match the original Python AAC API:

### Authentication
- `POST /aac/authentificate` - Login (username + secret)
- `POST /aac/authorize` - Login with app context
- `GET /aac/user/details?username=X&app=Y` - User details

### Users
- `POST /aac/user/create` - Create user
- `POST /aac/user/change` - Change user
- `POST /aac/user/delete` - Delete user
- `GET /aac/users/list` - List all users

### Branches
- `GET /aac/branches` - Get all branches
- `GET /aac/branch/subbranches?branch=X` - Sub-branches
- `POST /aac/branch/subbranch/add` - Add sub-branch
- `POST /aac/branch/delete` - Delete branch
- `GET /aac/branch/fswhitelist/get?branch=X` - Get whitelist
- `POST /aac/branch/fswhitelist/set` - Set whitelist
- `GET /aac/branch/roles/list?branch=X` - Branch roles
- `POST /aac/branch/role/create` - Create role
- `POST /aac/branch/role/delete` - Delete role
- `GET /aac/branch/employees/list?branch=X` - Employees

### Roles
- `GET /aac/role/funcsets?branch=X&role=Y` - Role funcsets
- `POST /aac/role/funcset/add` - Add funcset to role
- `POST /aac/role/funcset/remove` - Remove funcset from role

### Funcsets
- `GET /aac/funcsets` - List all funcsets
- `POST /aac/funcset/create` - Create funcset
- `POST /aac/funcset/delete` - Delete funcset
- `GET /aac/funcset/details?funcset=X` - Funcset details
- `POST /aac/funcset/function/add` - Add function
- `POST /aac/funcset/function/remove` - Remove function

### HR / Employees
- `POST /aac/hr/hire` - Hire employee
- `POST /aac/hr/fire` - Fire employee
- `GET /aac/hr/branch/positions?branch=X` - Positions report
- `POST /aac/hr/branch/position/create` - Create position
- `POST /aac/hr/branch/position/delete` - Delete position
- `GET /aac/positions?filter=X` - Get positions
- `GET /aac/emp/subbranches/list?username=X` - Employee sub-branches
- `GET /aac/emp/funcsets/list?username=X` - Employee funcsets
- `GET /aac/emp/functions/list?username=X` - Employee functions
- `GET /aac/emp/functions/review?username=X&props=Y` - Employee functions review

### Agents
- `POST /aac/agent/register` - Register agent
- `POST /aac/agent/movedown` - Move agent to sub-branch
- `POST /aac/agent/unregister` - Unregister agent
- `GET /aac/agent/details/xml?agent=X` - Agent details (XML)
- `GET /aac/agent/details/json?agent=X` - Agent details (JSON)
- `GET /aac/agents/list?branch=X` - List agents

### Functions Catalogue
- `GET /aac/functions/list?prop=X` - List functions by property
- `GET /aac/function/review?props=X&funcId=Y` - Review function
- `GET /aac/function/info?funcId=X` - Function definition
- `POST /aac/function/delete` - Delete function
- `POST /aac/function/upload/xmldescr` - Upload function XML
- `POST /aac/function/upload/xmlfile` - Upload function file
- `POST /aac/function/tagset/modify` - Modify function tags

### Test Runner
- `GET /aac/testrunner/states?states=S1,S2&durationEach=10` - Run test

## Project structure

```
lib/
  aac/
    application.ex          # OTP Application supervisor
    repo.ex                 # Ecto repository
    test_runner.ex          # GenServer for async test tasks
    schema/                 # Ecto schemas (data models)
      user.ex               # User (person) in people register
      user_change.ex        # User change history
      branch.ex             # Organizational branch
      branch_whitelist.ex   # Funcset whitelist per branch
      funcset.ex            # Function set
      funcset_function.ex   # Function in a funcset
      role.ex               # Role in a branch
      role_funcset.ex       # Funcset assigned to a role
      employee.ex           # Position/employee in branch
      agent.ex              # Registered agent
      agent_tag.ex          # Agent tag
      function_def.ex       # Function definition from catalogue
    business/
      data_keeper.ex        # Core business logic (port of dataKeeper.py)
  aac_web/
    endpoint.ex             # Phoenix endpoint
    router.ex               # HTTP routes
    cors_plug.ex            # CORS middleware
    controllers/            # Request handlers
      auth_controller.ex
      user_controller.ex
      branch_controller.ex
      funcset_controller.ex
      role_controller.ex
      employee_controller.ex
      agent_controller.ex
      function_controller.ex
      test_runner_controller.ex
      response_helper.ex    # HTTP status code mapping
priv/
  repo/
    migrations/             # Database schema
    seeds.exs               # Initial data (matches Python XML data)
config/
  config.exs                # Base configuration
  dev.exs                   # Development settings
  prod.exs                  # Production settings
  runtime.exs               # Runtime configuration
```

## Data model

The Python version stores data in XML files (`universe.xml`, `catalogues.xml`) and SQLite (`agents.db`).
This Elixir version unifies all storage into a single SQLite database with proper relational schema:

- **users** - People register (replaces `<person>` XML elements)
- **branches** - Organizational hierarchy (replaces `<branch>` XML tree)
- **funcsets** - Function set definitions
- **roles** - Role definitions per branch
- **employees** - Position assignments (vacant when person_id is NULL)
- **agents** - Device/service registrations
- **function_defs** - Function catalogue (preserves XML definitions)

## Response format

All endpoints return JSON with the same structure as the Python version:

```json
// Success
{"result": true, ...}

// Error
{"result": false, "reason": "ERROR-CODE", "warning": "Human readable message"}
```

HTTP status codes are mapped from reason codes (same as Python):
- 400: WRONG-FORMAT, WRONG-DATA
- 401: USER-UNKNOWN, OP-UNAUTHORIZED
- 403: WRONG-SECRET, SECRET-EXPIRED, ALREADY-EXISTS, FORBIDDEN-FOR-OP
- 404: FUNCTION-UNKNOWN, FUNCSET-UNKNOWN, BRANCH-UNKNOWN, etc.
- 405: NOT-ALLOWED
- 500: DATABASE-ERROR
