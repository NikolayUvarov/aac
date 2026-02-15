# AAC API Reference

Base URL: `http://<host>:<port>/aac`

All responses are JSON with `Content-Type: application/json; charset=utf-8`.
On success: `{"result": true, ...}`.
On error: `{"result": false, "reason": "<CODE>", "warning": "..."}` with appropriate HTTP status.

Special request modifiers:
- Header `X-Flush-Now: true` or query param `?flush=true` — force immediate disk save after this request.

---

## Authentication

### POST/GET `/aac/authorize`
Authenticate a user and optionally retrieve application-specific details.

| Parameter  | Source     | Required | Description                    |
|------------|-----------|----------|--------------------------------|
| `username` | form/args | yes      | User ID                        |
| `secret`   | form/args | yes      | SHA-256 hash of password+login |
| `app`      | query     | no       | Application name (`gAP`, `thePage`) for extra data |

### POST/GET `/aac/authentificate`
Same as `/aac/authorize` but does not return application-specific details.

---

## Users

### GET `/aac/users/list`
List all registered user IDs.

### GET `/aac/user/details`
| Parameter  | Required | Description |
|------------|----------|-------------|
| `username` | yes      | User ID     |
| `app`      | no       | Application name for extra data |

### POST `/aac/user/create`
| Parameter       | Required | Description |
|-----------------|----------|-------------|
| `username`      | yes      | New user ID |
| `secret`        | yes      | SHA-256 password hash |
| `operator`      | yes      | ID of the user performing the operation |
| `pswlifetime`   | no       | Password lifetime in days |
| `readablename`  | no       | Human-readable name |
| `sessionmax`    | no       | Session duration limit (minutes) |

### POST `/aac/user/change`
Same parameters as `/aac/user/create`. Updates the existing user.

### POST `/aac/user/delete`
| Parameter  | Required | Description |
|------------|----------|-------------|
| `username` | yes      | User to delete |
| `operator` | yes      | Operator performing the action |

---

## HR / Employees

### POST `/aac/hr/hire`
| Parameter  | Required | Description |
|------------|----------|-------------|
| `username` | yes      | User ID to hire |
| `branch`   | yes      | Branch ID |
| `position` | yes      | Role name for the position |
| `operator` | yes      | Operator |

### POST `/aac/hr/fire`
| Parameter  | Required | Description |
|------------|----------|-------------|
| `username` | yes      | User ID to fire |
| `operator` | yes      | Operator |

### POST `/aac/hr/branch/position/create`
| Parameter | Required | Description |
|-----------|----------|-------------|
| `branch`  | yes      | Branch ID |
| `role`    | yes      | Role name |

### POST `/aac/hr/branch/position/delete`
Same parameters. Deletes one vacant position.

### GET `/aac/hr/branch/positions`
| Parameter    | Required | Description |
|--------------|----------|-------------|
| `branch`     | yes      | Branch ID or `*ALL*` |
| `perRole`    | no       | `yes` for per-role breakdown |
| `onlyVacant` | no       | `yes` to show only vacant |

### GET `/aac/branch/employees/list`
| Parameter            | Required | Description |
|----------------------|----------|-------------|
| `branch`             | yes      | Branch ID |
| `includeSubBranches` | no       | `yes` to include sub-branches |

---

## Branches

### GET `/aac/branches`
List all branches with vacancy counts.

### GET `/aac/branch/subbranches`
| Parameter | Required | Description |
|-----------|----------|-------------|
| `branch`  | yes      | Parent branch (empty for root) |

### POST `/aac/branch/subbranch/add`
| Parameter   | Required | Description |
|-------------|----------|-------------|
| `branch`    | yes      | Parent branch ID |
| `subbranch` | yes      | New subbranch ID |

### POST `/aac/branch/delete`
| Parameter | Required | Description |
|-----------|----------|-------------|
| `branch`  | yes      | Branch ID to delete (must be empty) |

### GET `/aac/branch/fswhitelist/get`
| Parameter | Required | Description |
|-----------|----------|-------------|
| `branch`  | yes      | Branch ID |

### POST `/aac/branch/fswhitelist/set`
| Parameter    | Required | Description |
|--------------|----------|-------------|
| `branch`     | yes      | Branch ID |
| `propparent` | no       | `yes` to propagate parent funcsets |
| `white`      | no       | List of funcset IDs (multi-value) |

### GET `/aac/branch/roles/list`
| Parameter       | Required | Description |
|-----------------|----------|-------------|
| `branch`        | yes      | Branch ID |
| `inherited`     | no       | `yes` to include inherited roles |
| `withbranchids` | no       | `yes` to include defining branch |

---

## Roles

### POST `/aac/branch/role/create`
| Parameter | Required | Description |
|-----------|----------|-------------|
| `branch`  | yes      | Branch ID |
| `role`    | yes      | New role name |
| `duties`  | no       | Funcset IDs (multi-value) |

### POST `/aac/branch/role/delete`
| Parameter | Required | Description |
|-----------|----------|-------------|
| `branch`  | yes      | Branch ID |
| `role`    | yes      | Role name to delete |

### GET `/aac/role/funcsets`
| Parameter | Required | Description |
|-----------|----------|-------------|
| `branch`  | yes      | Branch ID |
| `role`    | yes      | Role name |

### POST `/aac/role/funcset/add`
| Parameter | Required | Description |
|-----------|----------|-------------|
| `branch`  | yes      | Branch ID |
| `role`    | yes      | Role name |
| `funcset` | yes      | Funcset ID to add |

### POST `/aac/role/funcset/remove`
Same parameters. Removes funcset from role.

---

## Function Sets

### GET `/aac/funcsets`
List all funcset IDs.

### POST `/aac/funcset/create`
| Parameter      | Required | Description |
|----------------|----------|-------------|
| `branch`       | yes      | Branch ID where to define |
| `funcset`      | yes      | New funcset ID |
| `readablename` | no       | Human-readable name |

### POST `/aac/funcset/delete`
| Parameter | Required | Description |
|-----------|----------|-------------|
| `funcset` | yes      | Funcset ID |

### GET `/aac/funcset/details`
| Parameter | Required | Description |
|-----------|----------|-------------|
| `funcset` | yes      | Funcset ID |

### POST `/aac/funcset/function/add`
| Parameter | Required | Description |
|-----------|----------|-------------|
| `funcset` | yes      | Funcset ID |
| `funcId`  | yes      | Function ID to add |

### POST `/aac/funcset/function/remove`
Same parameters. Removes function from funcset.

---

## Functions Catalogue

### GET `/aac/functions/list`
| Parameter | Required | Description |
|-----------|----------|-------------|
| `prop`    | yes      | Property: `id`, `name`, `title`, `description`, `callpath`, `method`, `contenttype` |

### GET `/aac/functions/review`
| Parameter | Required | Description |
|-----------|----------|-------------|
| `props`   | yes      | Comma-separated property names |

### GET `/aac/function/review`
| Parameter | Required | Description |
|-----------|----------|-------------|
| `props`   | yes      | Comma-separated property names |
| `funcId`  | yes      | Function ID |

### GET `/aac/function/info`
| Parameter  | Required | Description |
|------------|----------|-------------|
| `funcId`   | yes      | Function ID |
| `pure`     | no       | `yes` to return raw XML |
| `xsltref`  | no       | XSLT stylesheet URL |

### POST `/aac/function/upload/xmldescr`
| Parameter | Required | Description |
|-----------|----------|-------------|
| `xmltext` | yes      | XML function definition |

### POST `/aac/function/upload/xmlfile`
File upload field: `xmlfile` (XML file).

### POST `/aac/function/delete`
| Parameter | Required | Description |
|-----------|----------|-------------|
| `funcId`  | yes      | Function ID |

### POST `/aac/function/tagset/modify`
| Parameter | Required | Description |
|-----------|----------|-------------|
| `funcId`  | yes      | Function ID |
| `method`  | yes      | `SET`, `OR`, `AND`, `MINUS` |
| `tag`     | yes      | Tag values (multi-value) |

### GET `/aac/function/tagset/test`
Same parameters. Read-only preview of tagset operation.

---

## Employee Access Queries

### GET `/aac/emp/subbranches/list`
| Parameter    | Required | Description |
|--------------|----------|-------------|
| `username`   | yes      | User ID |
| `allLevels`  | no       | `yes` for all levels (default) |
| `excludeOwn` | no       | `yes` to exclude own branch |

### GET `/aac/emp/funcsets/list`
| Parameter  | Required | Description |
|------------|----------|-------------|
| `username` | yes      | User ID |

### GET `/aac/emp/functions/list`
| Parameter  | Required | Description |
|------------|----------|-------------|
| `username` | yes      | User ID |
| `prop`     | no       | Property to return (default: `id`) |

### GET `/aac/emp/functions/review`
| Parameter  | Required | Description |
|------------|----------|-------------|
| `username` | yes      | User ID |
| `props`    | yes      | Comma-separated properties |

---

## Agents

### POST `/aac/agent/register`
| Parameter  | Required | Description |
|------------|----------|-------------|
| `branch`   | yes      | Branch ID (or `*ROOT*`) |
| `agent`    | yes      | Agent ID |
| `descr`    | no       | Description |
| `location` | no       | Location |
| `tags`     | no       | Comma-separated tags |
| `extraxml` | no       | Extra info in XML format |

### POST `/aac/agent/movedown`
Same parameters. Moves agent to a subsidiary branch.

### POST `/aac/agent/unregister`
| Parameter | Required | Description |
|-----------|----------|-------------|
| `agent`   | yes      | Agent ID |

### GET `/aac/agent/details/xml`
| Parameter | Required | Description |
|-----------|----------|-------------|
| `agent`   | yes      | Agent ID |

Returns XML with `Content-Type: text/xml`.

### GET `/aac/agent/details/json`
| Parameter | Required | Description |
|-----------|----------|-------------|
| `agent`   | yes      | Agent ID |

### GET `/aac/agents/list`
| Parameter      | Required | Description |
|----------------|----------|-------------|
| `branch`       | yes      | Branch ID or `*ALL*` |
| `subsidinaries`| no       | `yes` to include subsidiaries |
| `location`     | no       | `yes` to include branch info |

---

## Error Codes

| Code               | HTTP | Description |
|--------------------|------|-------------|
| `WRONG-FORMAT`     | 400  | Missing or invalid parameter |
| `WRONG-DATA`       | 400  | Invalid data format |
| `USER-UNKNOWN`     | 401  | User not found |
| `WRONG-SECRET`     | 403  | Incorrect password |
| `SECRET-EXPIRED`   | 403  | Password expired |
| `ALREADY-EXISTS`   | 403  | Resource already exists |
| `USER-EMPLOYED`    | 403  | User is still employed |
| `ALREADY-UNEMPLOYED`| 403 | User not employed |
| `FUNCTION-UNKNOWN` | 404  | Function not in catalogue |
| `FUNCSET-UNKNOWN`  | 404  | Funcset not found |
| `ROLE-UNKNOWN`     | 404  | Role not defined |
| `BRANCH-UNKNOWN`   | 404  | Branch not found |
| `AGENT-UNKNOWN`    | 404  | Agent not registered |
| `NOT-IN-SET`       | 404  | Item not in set |
| `NOT-ALLOWED`      | 405  | Operation not permitted |
| `DATABASE-ERROR`   | 500  | Internal data inconsistency |
| `OP-UNAUTHORIZED`  | 401  | Operator not authenticated |
| `OPERATOR-UNKNOWN` | 401  | Operator not found |
| `FORBIDDEN-FOR-OP` | 403  | Operator lacks authority |
