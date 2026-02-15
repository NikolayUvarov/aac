# Предложения по миграции хранилища данных

## Текущая архитектура

Сейчас данные хранятся в двух XML-файлах (`universe.xml`, `catalogues.xml`), загружаемых
целиком в память при старте.  Агенты уже вынесены в SQLite (`agents.db`).

### Достоинства текущей схемы
- Простота: вся структура доступна через XPath без ORM/SQL
- Мгновенные чтения из памяти
- Иерархия ветвей (branches) естественно ложится в XML-дерево
- Атомарность записи через "castling" (temp -> rename)
- Объём данных до десятков мегабайт легко помещается в RAM

### Ограничения
- Нет индексов — XPath обходит всё дерево при каждом запросе
- Запись целого файла при каждом изменении (даже с deferred save — пишется всё дерево)
- Конкурентный доступ только через asyncio.Lock (один writer)
- Нет транзакций: при сбое между шагами castling возможна потеря данных
- Масштабирование: при десятках тысяч пользователей XPath-запросы станут узким местом

---

## Вариант 1: SQLite (рекомендуемый для масштаба до сотен тысяч записей)

### Схема таблиц

```sql
-- Иерархия ветвей (closure table для поддержки вложенности)
CREATE TABLE branches (
    id          TEXT PRIMARY KEY,
    parent_id   TEXT REFERENCES branches(id),
    propagate_parent_wl  INTEGER NOT NULL DEFAULT 0  -- boolean
);

CREATE TABLE branch_closure (
    ancestor_id    TEXT NOT NULL REFERENCES branches(id),
    descendant_id  TEXT NOT NULL REFERENCES branches(id),
    depth          INTEGER NOT NULL,
    PRIMARY KEY (ancestor_id, descendant_id)
);

-- Пользователи
CREATE TABLE users (
    id              TEXT PRIMARY KEY,
    secret          TEXT NOT NULL,
    psw_changed_at  INTEGER NOT NULL,
    expire_at       INTEGER,              -- NULL = без срока
    failures        INTEGER NOT NULL DEFAULT 0,
    readable_name   TEXT NOT NULL DEFAULT '',
    session_max     INTEGER NOT NULL DEFAULT 60,
    created_by      TEXT NOT NULL,
    created_at      INTEGER NOT NULL,
    last_error      INTEGER,
    last_auth_success INTEGER
);

CREATE TABLE user_changes (
    id       INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id  TEXT NOT NULL REFERENCES users(id),
    changed_by TEXT NOT NULL,
    changed_at INTEGER NOT NULL
);

-- Роли
CREATE TABLE roles (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    branch_id   TEXT NOT NULL REFERENCES branches(id),
    name        TEXT NOT NULL,
    UNIQUE(branch_id, name)
);

-- Функциональные наборы
CREATE TABLE funcsets (
    id            TEXT PRIMARY KEY,
    branch_id     TEXT NOT NULL REFERENCES branches(id),
    readable_name TEXT NOT NULL DEFAULT ''
);

CREATE TABLE funcset_functions (
    funcset_id  TEXT NOT NULL REFERENCES funcsets(id) ON DELETE CASCADE,
    func_id     TEXT NOT NULL,
    PRIMARY KEY (funcset_id, func_id)
);

-- Привязка функциональных наборов к ролям
CREATE TABLE role_funcsets (
    role_id    INTEGER NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    funcset_id TEXT NOT NULL REFERENCES funcsets(id),
    PRIMARY KEY (role_id, funcset_id)
);

-- Штатные позиции и сотрудники
CREATE TABLE positions (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    branch_id   TEXT NOT NULL REFERENCES branches(id),
    role_name   TEXT NOT NULL,
    person_id   TEXT REFERENCES users(id)  -- NULL = вакансия
);

-- Белый список функциональных наборов для ветви
CREATE TABLE branch_fs_whitelist (
    branch_id   TEXT NOT NULL REFERENCES branches(id),
    funcset_id  TEXT NOT NULL REFERENCES funcsets(id),
    PRIMARY KEY (branch_id, funcset_id)
);

-- Каталог функций (определения)
CREATE TABLE functions_catalogue (
    id           TEXT PRIMARY KEY,
    name         TEXT,
    title        TEXT,
    descr        TEXT,
    tags         TEXT,                -- comma-separated
    call_method  TEXT,
    call_url     TEXT,
    body_content_type TEXT,
    definition_xml    TEXT NOT NULL   -- полный XML для обратной совместимости
);

-- Агенты (уже в SQLite, оставляем как есть)
```

### Преимущества
- Полноценные транзакции (ACID)
- Индексы на часто запрашиваемые поля (O(log n) вместо O(n))
- Инкрементальная запись — не нужно переписывать весь файл
- WAL-режим: параллельные чтения не блокируют запись
- Миграция агентов не нужна — уже в SQLite
- Встроен в Python — нет внешних зависимостей

### Стратегия миграции
1. Создать `sqliteKeeper.py` с тем же API, что и `configDataKeeper`
2. Написать скрипт `migrate_xml_to_sqlite.py` для разового импорта
3. Переключить `aac.py` на новый keeper через конфигурацию
4. Сохранить `dataKeeper.py` для обратной совместимости

### Closure table для иерархии ветвей
Closure table позволяет эффективно выполнять запросы вида:
- Все потомки ветви: `SELECT descendant_id FROM branch_closure WHERE ancestor_id = ?`
- Все предки: `SELECT ancestor_id FROM branch_closure WHERE descendant_id = ?`
- Глубина вложенности: `WHERE depth = 1` (только прямые потомки)

Это заменяет XPath `descendant::branch` и `ancestor::branch`.

---

## Вариант 2: PostgreSQL (для высокой нагрузки и многосерверности)

### Когда нужен
- Несколько экземпляров сервиса (горизонтальное масштабирование)
- Десятки тысяч одновременных соединений
- Необходимость репликации и резервного копирования на уровне СУБД

### Особенности
- Иерархию ветвей можно хранить через `ltree` (расширение) или CTE-рекурсии
- JSONB для произвольных атрибутов (extra в агентах)
- Advisory locks для координации записей между инстансами
- Схема таблиц аналогична SQLite, но с нативными типами (BOOLEAN, TIMESTAMP)

### Дополнительные зависимости
- `asyncpg` или `psycopg[binary]` + `psycopg_pool`
- Внешний PostgreSQL-сервер

### Стоит рассматривать только если
- Планируется > 1 инстанса приложения
- Объём данных превысит 100 МБ
- Нужна geo-репликация или высокая доступность

---

## Вариант 3: Гибридный — XML для конфигурации, SQLite для данных

### Идея
- `catalogues.xml` (определения функций) — редко меняется, удобен для ручного
  редактирования, остаётся в XML
- `universe.xml` (пользователи, ветви, роли, штатное расписание) — часто меняется
  программно, переносится в SQLite

### Преимущества
- Минимальная переработка: каталог функций продолжает работать через lxml
- Транзакции и индексы для часто меняющихся данных
- Обратная совместимость для инструментов, работающих с XML-каталогом

---

## Рекомендация

Для текущего масштаба (десятки пользователей, мегабайты данных) XML работает.
Если планируется рост:

| Масштаб                | Рекомендация        |
|------------------------|---------------------|
| До ~100 пользователей  | Оставить XML + deferred save |
| 100–10 000 пользователей | Вариант 1 (SQLite) или Вариант 3 (гибрид) |
| > 10 000 или multi-instance | Вариант 2 (PostgreSQL) |

Первый шаг в любом случае — выделить интерфейс (абстрактный класс / протокол)
`DataKeeperInterface`, чтобы `aac.py` не зависел от конкретной реализации хранилища.
Это позволит переключать бекенды без изменения бизнес-логики.
