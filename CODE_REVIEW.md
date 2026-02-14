# Code Review: AAC (Authenticate, Authorize, Configure)

## Overview

AAC is a hierarchical authentication, authorization, and configuration management system built on **Quart** (async Flask), with XML (lxml) as primary data storage and SQLite for agent management. The codebase consists of ~2,700 lines of Python across 5 modules, 43 Jinja2 templates, and a small set of frontend JS files.

---

## 1. Critical Security Issues

### 1.1 XPath Injection (HIGH)

Throughout `dataKeeper.py`, user-supplied values are interpolated directly into XPath expressions via f-strings. This allows an attacker to manipulate the XPath query logic.

**Examples:**
- `dataKeeper.py:71` — `etree.XPath(f"/universe/registers/people_register/person[@id='{userid}']")`
- `dataKeeper.py:251` — `etree.XPath(f"//branch[employees/employee/@person='{userid}']/@id")`
- `dataKeeper.py:269` — `etree.XPath(f"//branch[@id='{branch_id}']/roles/role/@name")`

A `userid` value such as `' or '1'='1` would break the predicate. This pattern exists in nearly every method of `configDataKeeper`.

**Recommendation:** Validate all user inputs against a strict whitelist (e.g., alphanumeric + limited characters), or use parameterized XPath queries.

### 1.2 No Authentication on Administrative Endpoints (HIGH)

Endpoints like `/aac/user/create`, `/aac/user/delete`, `/aac/hr/fire`, `/aac/hr/hire`, `/aac/branch/delete`, etc. accept an `operator` parameter from the request form, but the only check is whether a user with that ID exists in the database (`_get_operatorS_node`). There is no verification that the current request actually comes from that authenticated operator.

**Anyone can impersonate any operator** by simply passing their username in the form data.

- `aac.py:152` — `storage.createUser(username, secret, op, ...)`
- `dataKeeper.py:726` — `self._get_operatorS_node(operator)` only checks `_getUserNode(operator) is not None`

### 1.3 Client-Side Password Hashing Without Server-Side Hashing (HIGH)

The authentication form (`form4_userAndPass.jinja:9`) hashes the password client-side with SHA256 and sends the hash as `secret`. The server stores this hash directly in XML:

- `dataKeeper.py:736` — `unode.set("secret", secret)`
- `dataKeeper.py:138` — `if secret != unode.get('secret'):` (plain comparison)

This means:
- Whoever has read access to `universe.xml` sees all password hashes.
- SHA256 is **not** a password hashing algorithm; it lacks salting and is designed to be fast, making brute-force attacks trivial.
- If the hash is intercepted in transit (no HTTPS enforcement), it can be replayed directly.

**Recommendation:** Use bcrypt/scrypt/argon2 on the server side. Client-side hashing provides no meaningful security.

### 1.4 Secrets Logged in Plaintext (MEDIUM)

The `aac_rq_handler` decorator logs the full raw request body on every request:

- `aac.py:64` — `logger.info(f"Request is {fwrk.request}, raw body of content type {repr(fwrk.request.content_type)} is {await fwrk.request.get_data()}")`

This means passwords/secrets are written to `LOGS/aac.log` in plaintext.

### 1.5 XSS / XML Injection via `xsltref` Parameter (MEDIUM)

- `aac.py:426` — `hdr = f'<?xml version="1.0" encoding="UTF-8"?>\n<?xml-stylesheet type="text/xsl" href="{xsltref}"?>\n\n'`

The `xsltref` query parameter is directly interpolated into XML output without any sanitization, allowing injection of arbitrary processing instructions or content.

### 1.6 Debug Mode in Production (MEDIUM)

- `aac.py:1076` — `debug=True` is hardcoded in the `run_task()` call. This exposes detailed stack traces to clients and may enable the interactive debugger.

### 1.7 No CSRF Protection (MEDIUM)

All state-modifying endpoints accept POST requests without any CSRF token verification. Combined with the CORS whitelist approach, this leaves the application vulnerable to cross-site request forgery from non-whitelisted origins (browsers may still send the request; CORS only controls reading the response).

### 1.8 No Rate Limiting (LOW)

The `/aac/authentificate` endpoint counts failures but has no lockout mechanism or rate limiting. An attacker can brute-force credentials at full speed.

---

## 2. Bugs

### 2.1 `NameError`: `repe` instead of `repr`

- **File:** `dataKeeper.py:323`
- **Code:** `f"Funcset {repr(funcset_id)} is not in role {repe(role_name)} of {repr(branch_id)}"`
- **Impact:** `roleFuncsetRemove()` will crash with `NameError: name 'repe' is not defined` when a funcset is not found in a role.

### 2.2 `NameError`: `brachId` instead of `branchId`

- **File:** `dataKeeper.py:970`
- **Code:** `logger.warning(f"Branch '{brachId}' is unknown")`
- **Impact:** `branchEmployeesList()` will crash with `NameError` when an unknown branch is requested, instead of returning the intended error response.

### 2.3 Missing f-string prefix in `getSubBranchesOfAgent`

- **File:** `dataKeeper.py:1140-1142`
- **Code:**
  ```python
  logger.info("requested subbranches of owner of agent {repr(agentid)} that is {repr(branch_id)}")
  ...
  logger.info("result is {repr(ret)} with length {len(ret)}")
  ```
- **Impact:** Logs will contain the literal text `{repr(agentid)}` instead of the actual values. Not a crash, but defeats the purpose of logging.

### 2.4 Incorrect `await` on synchronous property

- **File:** `aac.py:995`
- **Code:** `branch = await fwrk.request.args.get("filter", default="")`
- **Impact:** `request.args` is a synchronous `MultiDict`. The `await` is applied to the string returned by `.get()`, which will raise `TypeError` in Python because strings are not awaitable.

### 2.5 Self-test uses wrong constructor signature

- **File:** `dataKeeper.py:1266`
- **Code:** `test = configDataKeeper("DATA/everything.xml","DATA/catalogues.xml")`
- **Impact:** The constructor expects `(data_catalogue, default_sess_max)`, not two file paths. Running `python dataKeeper.py` will fail.

### 2.6 Wrong dict referenced in log message

- **File:** `testRunner.py:61`
- **Code:** `logger.info(f"Task {tId} done, finished tasks storage is: {type(self).__running_tasks.keys()}")`
- **Impact:** Should log `__done_tasks.keys()` to show the finished tasks, not `__running_tasks` (which the task was just removed from).

---

## 3. Architecture and Design Issues

### 3.1 XML as Primary Database

Using `universe.xml` as the main data store has fundamental limitations:
- **No concurrency control** — simultaneous requests can cause data corruption (read-modify-write race conditions in `_save()`).
- **No ACID guarantees** — partial writes during `_save()` can corrupt the file (the "castling" mechanism helps but is not atomic on all filesystems).
- **Performance** — every operation re-traverses the full XML tree. This will degrade linearly with data volume.

### 3.2 Synchronous Blocking I/O in Async Application

Despite using Quart (async), all data operations are synchronous:
- `_save()` does blocking file I/O (`open()`, `write()`, `os.rename()`).
- `load()` does blocking XML parsing.
- SQLite operations in `agentsKeeper.py` are also synchronous.

This blocks the event loop and negates the benefits of the async framework.

### 3.3 Global Mutable State

- `storage` — `aac.py:23`, set in `main()`, used by all route handlers.
- `_aac_cors_whitelist` — `aac.py:1068`, set in `main()`, used by `after_request`.
- `cfgDict` — `aac.py:1049`, set in `main()`, used by route handlers.

This makes the application difficult to test, prevents running multiple instances, and creates implicit coupling.

### 3.4 No Automated Tests

There is no test suite, no `tests/` directory, no `pytest`/`unittest` configuration. The only "tests" are ad-hoc `__main__` blocks (which themselves contain bugs — see 2.5).

### 3.5 No Dependency Management

No `requirements.txt`, `pyproject.toml`, `setup.py`, or `Pipfile` exists. Dependencies (Quart, lxml, PyYAML, sqlite3) are not documented.

### 3.6 No API Versioning

All endpoints are under `/aac/` with no version prefix. Any breaking change will affect all clients simultaneously.

---

## 4. Code Quality

### 4.1 Naming Inconsistency

The codebase mixes several naming conventions:
- **snake_case:** `user_create`, `branch_employees_list`, `get_user_reg_details`
- **camelCase:** `funcsetCreate`, `roleFuncsetAdd`, `empFuncsetsList`
- **PascalCase abbreviations:** `getBranchFsWhiteList`

Within a single class (`configDataKeeper`), both `createUser` and `get_user_reg_details` coexist.

### 4.2 Duplicate Code Patterns

Many route handlers in `aac.py` follow a nearly identical pattern:
1. Check for GET -> render form.
2. Read form data.
3. Call storage method.
4. Wrap in `add_respcode_by_reason()`.

This could be reduced with a generic handler or class-based views.

### 4.3 Bare `except` Clauses

- `aac.py:1008` — `except:` in `adjustLogging()`
- `aac.py:1052` — `except:` in `main()`

Bare `except` catches `SystemExit`, `KeyboardInterrupt`, etc. Use `except Exception:` at minimum.

### 4.4 Commented-Out Code

Significant blocks of commented-out code remain throughout:
- `aac.py:6,10,118,464,485,813-814,1007,1019`
- `dataKeeper.py:693-696,999`
- `agentsKeeper.py:1-6,114-122`

### 4.5 No Type Hints

No functions or methods use type annotations, making the API contracts implicit and hard to verify with static analysis tools.

### 4.6 No Docstrings

None of the classes or public methods have docstrings. The only documentation is the brief `README.md`.

### 4.7 `hashString2Hex` Function is Unused

- `aac.py:41-44` — The function `hashString2Hex` is defined but never called anywhere in the codebase.

### 4.8 Magic Strings

Error reason codes (`"WRONG-FORMAT"`, `"USER-UNKNOWN"`, etc.) are repeated as string literals throughout. These should be constants or an enum.

---

## 5. Frontend

### 5.1 Synchronous XMLHttpRequest

- `f2html.js:9` — `xhttp.open(method, url, false)` uses synchronous XHR, which blocks the browser's main thread and is deprecated in modern browsers.

### 5.2 SHA256 Implementation Correctness

- `minicrypto.js` contains a hand-rolled SHA256 implementation. While compact, using `crypto.subtle.digest()` (Web Crypto API) would be more reliable and performant.

### 5.3 Global Variable Leak

- `f2html.js:9` — `xhttp = new XMLHttpRequest()` without `var`/`let`/`const` creates a global variable.

### 5.4 Typo in Serializer

- `f2html.js:53` — `string(value)` should be `String(value)` (capital S). This will throw `ReferenceError` at runtime.

---

## 6. Summary of Severity

| Category | Critical | High | Medium | Low |
|----------|----------|------|--------|-----|
| Security | 0 | 3 | 4 | 1 |
| Bugs | 0 | 2 | 3 | 1 |
| Architecture | 0 | 2 | 2 | 2 |
| Code Quality | 0 | 0 | 3 | 5 |

**Top priorities to address:**
1. XPath injection throughout `dataKeeper.py`
2. Missing authentication on administrative endpoints
3. Proper server-side password hashing
4. Fix `NameError` bugs (items 2.1, 2.2, 2.4)
5. Remove `debug=True` from production
6. Stop logging request bodies containing secrets
