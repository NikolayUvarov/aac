# AAC — Authenticate, Authorize, Configure

## Назначение

AAC — внутренний API-сервис для управления аутентификацией, авторизацией и хранения конфигурации. Предоставляет единую точку управления пользователями, их полномочиями и конфигурацией функций для других приложений организации.

## Архитектура

```
┌──────────────────────────────────────────────────────┐
│  Приложения-потребители (gAP, thePage, ...)          │
│  Обращаются к AAC за авторизацией и конфигурацией    │
└──────────────┬───────────────────────────────────────┘
               │ HTTP API (JSON)
┌──────────────▼───────────────────────────────────────┐
│  aac.py — Quart web-сервер                           │
│  Маршрутизация, декоратор aac_rq_handler, CORS       │
├──────────────────────────────────────────────────────┤
│  dataKeeper.py — бизнес-логика и хранение            │
│  Работа с XML-деревом (lxml), XPath-запросы          │
├──────────────────────────────────────────────────────┤
│  agentsKeeper.py — управление агентами               │
│  SQLite (agents.db): таблицы Agents, Tags            │
├──────────────────────────────────────────────────────┤
│  Хранилище данных                                    │
│  ├── universe.xml — оргструктура + пользователи      │
│  └── catalogues.xml — каталог описаний функций       │
└──────────────────────────────────────────────────────┘
```

## Модель данных

### Иерархия веток (branches)

Организационная структура представлена деревом веток. Каждая ветка содержит:

```
<branch id="Bank1">
    <deffuncsets>     — определения наборов функций (funcsets), локальных для ветки
    <func_white_list> — фильтр: какие funcsets родителя доступны в этой ветке
    <employees>       — должности (positions), могут быть вакантными или занятыми
    <roles>           — роли, определяющие какие funcsets доступны сотруднику
    <branches>        — дочерние ветки
</branch>
```

Пример дерева:
```
top level administration
├── report-branch
│   ├── report-branch-DEF
│   └── report-branch-client1
├── Bank1
│   └── Bank1|Office1
├── Bank2
└── IndentTest1
    └── IndentTest2
```

### Наследование полномочий

Ключевой механизм системы — контролируемое наследование funcsets по дереву веток:

```
Ветка-родитель (определяет funcsets: fs1, fs2, fs3)
│
└── Дочерняя ветка
        func_white_list:
            propagateParent="yes" → берёт все funcsets родителя как есть
            propagateParent="no"  → берёт только перечисленные в white_list

        Итого доступные funcsets = (локально определённые) ∪ (отфильтрованные от родителя)
```

Роли также наследуются: если роль не переопределена в текущей ветке, берётся определение из ближайшего предка.

### Цепочка авторизации

```
Пользователь
    → назначен на должность (position) в ветке
        → должность привязана к роли (role)
            → роль содержит список funcsets
                → funcsets фильтруются через white_list ветки
                    → funcset содержит конкретные функции (functions)
```

### Пользователи (people_register)

Хранятся отдельно от оргструктуры (нормализация). Атрибуты:
- `id` — уникальный идентификатор
- `secret` — SHA256-хеш (клиентский: `sha256(password + username)`)
- `pswChangedAt` — время последней смены пароля (unix timestamp)
- `expireAt` — время истечения пароля (опционально)
- `failures` — счётчик неудачных попыток входа
- `readableName` — отображаемое имя
- `sessionMax` — максимальная длительность сессии (минуты)
- `createdBy`, `createdAt` — кем и когда создан
- вложенные `<changed>` — история изменений

### Каталог функций (catalogues.xml)

Описания функций в XML-формате. Каждая функция содержит:
- Входные параметры (`<in>`) с типами и валидацией
- Описание API-вызова (`<call>`) — URL, метод, тело запроса
- Описание результата (`<out>`) — парсинг ответа, обработка промежуточных состояний
- Метаданные: `id`, `name`, `title`, `descr`, `tags`

Функции используются приложениями-потребителями для динамического построения UI и выполнения вызовов.

### Агенты (agents.db)

Внешние системы/устройства, привязанные к веткам. Хранятся в SQLite:
- `agent_id` — идентификатор
- `branch` — ветка-владелец
- `descr`, `location` — описание и местоположение
- `extra` — произвольные данные в XML-формате
- теги (таблица Tags)

Агенты могут перемещаться вниз по дереву веток (movedown).

## API

Все эндпоинты под префиксом `/aac/`. Формат ответов — JSON: `{"result": true/false, ...}`.

### Аутентификация
| Метод | Путь | Описание |
|-------|------|----------|
| POST | `/aac/authentificate` | Проверка credentials (только аутентификация) |
| POST | `/aac/authorize` | Аутентификация + данные авторизации для приложения |

### Управление пользователями
| Метод | Путь | Описание |
|-------|------|----------|
| POST | `/aac/user/create` | Регистрация нового пользователя |
| POST | `/aac/user/change` | Изменение данных пользователя |
| POST | `/aac/user/delete` | Удаление пользователя |
| GET | `/aac/user/details` | Детали регистрации пользователя |
| GET | `/aac/users/list` | Список всех пользователей |

### Кадровые операции
| Метод | Путь | Описание |
|-------|------|----------|
| POST | `/aac/hr/hire` | Назначение на должность |
| POST | `/aac/hr/fire` | Увольнение |
| POST | `/aac/hr/branch/position/create` | Создание вакансии |
| POST | `/aac/hr/branch/position/delete` | Удаление вакантной должности |
| GET | `/aac/hr/branch/positions` | Отчёт по должностям |

### Ветки
| Метод | Путь | Описание |
|-------|------|----------|
| GET | `/aac/branches` | Все ветки |
| GET | `/aac/branch/subbranches` | Дочерние ветки |
| POST | `/aac/branch/subbranch/add` | Добавить дочернюю ветку |
| POST | `/aac/branch/delete` | Удалить ветку |
| GET | `/aac/branch/roles/list` | Роли ветки |
| POST | `/aac/branch/role/create` | Создать роль |
| POST | `/aac/branch/role/delete` | Удалить роль |
| GET | `/aac/branch/fswhitelist/get` | White-list funcsets |
| POST | `/aac/branch/fswhitelist/set` | Установить white-list |
| GET | `/aac/branch/employees/list` | Сотрудники ветки |

### Наборы функций (funcsets)
| Метод | Путь | Описание |
|-------|------|----------|
| GET | `/aac/funcsets` | Все funcsets |
| POST | `/aac/funcset/create` | Создать funcset |
| POST | `/aac/funcset/delete` | Удалить funcset |
| GET | `/aac/funcset/details` | Содержимое funcset |
| POST | `/aac/funcset/function/add` | Добавить функцию в funcset |
| POST | `/aac/funcset/function/remove` | Убрать функцию из funcset |

### Функции (каталог)
| Метод | Путь | Описание |
|-------|------|----------|
| GET | `/aac/functions/list` | Список функций по свойству |
| GET | `/aac/functions/review` | Обзор свойств функций |
| GET | `/aac/function/info` | XML-определение функции |
| POST | `/aac/function/upload/xmldescr` | Загрузка описания (текст) |
| POST | `/aac/function/upload/xmlfile` | Загрузка описания (файл) |
| POST | `/aac/function/delete` | Удаление описания функции |
| POST | `/aac/function/tagset/modify` | Изменение тегов функции |
| GET | `/aac/function/tagset/test` | Тестовая операция над тегами |

### Роли и funcsets
| Метод | Путь | Описание |
|-------|------|----------|
| GET | `/aac/role/funcsets` | Funcsets роли |
| POST | `/aac/role/funcset/add` | Добавить funcset к роли |
| POST | `/aac/role/funcset/remove` | Убрать funcset у роли |

### Данные сотрудника (вычисляемые)
| Метод | Путь | Описание |
|-------|------|----------|
| GET | `/aac/emp/subbranches/list` | Доступные ветки сотрудника |
| GET | `/aac/emp/funcsets/list` | Доступные funcsets |
| GET | `/aac/emp/functions/list` | Доступные функции |
| GET | `/aac/emp/functions/review` | Обзор свойств доступных функций |

### Агенты
| Метод | Путь | Описание |
|-------|------|----------|
| POST | `/aac/agent/register` | Регистрация агента в ветке |
| POST | `/aac/agent/movedown` | Перемещение агента в дочернюю ветку |
| POST | `/aac/agent/unregister` | Удаление агента |
| GET | `/aac/agent/details/xml` | Детали агента (XML) |
| GET | `/aac/agent/details/json` | Детали агента (JSON) |
| GET | `/aac/agents/list` | Список агентов по ветке |

### Тестовый раннер
| Метод | Путь | Описание |
|-------|------|----------|
| GET | `/aac/testrunner/states` | Запуск/опрос тестовой задачи с промежуточными состояниями |

## Приложения-потребители

При вызове `/aac/authorize?app=<name>` возвращается расширенный ответ в зависимости от приложения:

- **gAP** — получает: branches, positions, func_groups, functions (с callpath и method), agents
- **thePage** — получает: funcsets с вложенными functions (id, name, title)

## Конфигурация

Файл `config/general.yaml`:
- `default_run_location` — профиль запуска по умолчанию
- `session_max_default` — время сессии по умолчанию (минуты)
- `debug` — режим отладки (по умолчанию false)
- `run_locations` — профили (порт, CORS whitelist)

Выбор профиля: аргумент командной строки `-runat=<location>`.

## Хранение данных

- **universe.xml** — оргструктура и пользователи; атомарная запись через «castling» (temp → backup → replace)
- **catalogues.xml** — описания функций; аналогичный механизм записи
- **agents.db** — SQLite для агентов и тегов

Файлы `DATA.vanila/` и `config.vanila/` — эталонные копии для начальной настройки.

## Запуск

```bash
cd aac
./initial_setup.sh    # копирование vanila → рабочие файлы
./run_aac.sh          # запуск сервера
```

Зависимости: Python 3, Quart, lxml, PyYAML.
