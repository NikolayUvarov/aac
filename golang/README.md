# AAC (Go variant)

Папка `golang/` содержит альтернативную реализацию backend-а на Go для системы AAC.

Что реализовано:
- HTTP API с эндпоинтами из `aac.py`.
- Хранилище на `universe.xml`, `catalogues.xml` через XPath (`xmlquery`).
- Агенты (`agents.db`) через SQLite (`modernc.org/sqlite`).
- Вспомогательный таскраннер (`/aac/testrunner/states`).

Базовый запуск:
- `go run . -runat=public-internet`

Сервис ожидает те же конфиги и данные (`config/general.yaml`, `DATA/...`) в корне репозитория.
