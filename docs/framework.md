# Раскладка приложения

```lua
-- bootstrap/app.lua — роль приложения; config.yaml подключает её: roles: [roles.httpd, bootstrap.app]
return require('tnt.framework').new({ name = 'demo', dependencies = { 'roles.httpd' } })
-- остальное — по соглашению: config/, routes/, database/, resources/views/, lang/, public/
```

Приложение на Tarantool 3 — это роль, а собирает её из объявления —
функций и таблиц — ядро [`tnt-kernel`](https://github.com/tnt-skein/tnt-kernel):
контейнер, граница HTTP, функции iproto, журнал, подъём схемы, применение
и останов — там. `tnt-framework` берёт это объявление из каталогов
и списков приложения: настройки из окружения — `config/`, провайдеры —
`bootstrap/providers.lua`, модели — `app/models`, миграции
и наполнители — `database/`, маршруты, слои и функции iproto — `routes/`,
страницы — `resources/views`, переводы — `lang/`, файлы для браузера —
`public/`. Разделы настроек он превращает в службы контейнера — клиент
Redis, драйвер базы, кэш, ограничитель частоты, почту, диски и сессии, —
связанные между собой аргументами.

Зависимости: [`tnt-kernel`](https://github.com/tnt-skein/tnt-kernel)
(роль из объявления), [`tnt-di`](https://github.com/tnt-skein/tnt-di)
(контейнер), [`tnt-config`](https://github.com/tnt-skein/tnt-config)
и [`tnt-env`](https://github.com/tnt-skein/tnt-env) (настройки, окружение,
собранные заранее файлы), [`tnt-template`](https://github.com/tnt-skein/tnt-template)
(страницы), [`tnt-i18n`](https://github.com/tnt-skein/tnt-i18n)
и [`tnt-error`](https://github.com/tnt-skein/tnt-error) (переводы и слово
отказа), [`tnt-schema`](https://github.com/tnt-skein/tnt-schema)
и [`tnt-model`](https://github.com/tnt-skein/tnt-model) (шаги схемы
и модели), [`tnt-console`](https://github.com/tnt-skein/tnt-console)
(команды узла), [`tnt-debug`](https://github.com/tnt-skein/tnt-debug)
(показ значения `@dump`), [`tnt-downtime`](https://github.com/tnt-skein/tnt-downtime)
(режим обслуживания), [`tnt-middleware`](https://github.com/tnt-skein/tnt-middleware)
(слой `cors`), [`tnt-session`](https://github.com/tnt-skein/tnt-session)
(сессии), [`tnt-cache`](https://github.com/tnt-skein/tnt-cache),
[`tnt-throttle`](https://github.com/tnt-skein/tnt-throttle),
[`tnt-redis`](https://github.com/tnt-skein/tnt-redis),
[`tnt-postgres`](https://github.com/tnt-skein/tnt-postgres),
[`tnt-mysql`](https://github.com/tnt-skein/tnt-mysql),
[`tnt-mail`](https://github.com/tnt-skein/tnt-mail),
[`tnt-files`](https://github.com/tnt-skein/tnt-files)
и [`tnt-s3`](https://github.com/tnt-skein/tnt-s3) (службы по разделам
настроек), [`tnt-log`](https://github.com/tnt-skein/tnt-log) (журнал),
[`tnt-clock`](https://github.com/tnt-skein/tnt-clock) (часы вне узла),
[`tnt-must`](https://github.com/tnt-skein/tnt-must) (проверки объявления)
и [`tnt-external`](https://github.com/tnt-skein/tnt-external) (подмена
смены учётки в проверках). Клиент Redis, драйверы базы, почта и клиент
S3 грузятся, только когда раздел настроек их назвал; роки `pg` и `mysql`
под драйверами ставит приложение рецептом `tnt-postgres` и `tnt-mysql`.

## Зачем пакет

Роль из объявления собрать можно и руками: список маршрутов, список шагов
схемы, сборщики контейнера. Но у каждого приложения этот список один
и тот же, и растёт он вместе с приложением: новый файл маршрутов надо
не забыть подключить, новую миграцию — вписать под своим номером, новый
раздел настроек — прочитать из окружения и отдать службе. Пакет делает
это один раз:

- **Одно место для каждой вещи.** Приложение с обычной раскладкой
  объявляется одним именем: где лежат маршруты, миграции и страницы,
  знает соглашение, и файл на своём месте подключается сам. Что взято
  по соглашению, показывает `role.layout()` — умолчание не молчит.
- **Опечатка — при загрузке.** Файл настроек, вернувший не функцию,
  провайдер с незнакомым полем, миграция без номера, наполнитель, ждущий
  несуществующего, незнакомое поле объявления — ошибка при загрузке модуля
  роли, а не на первом запросе в бою.
- **Службы по настройкам, связь — аргументом.** Раздел `config/redis.lua` —
  клиент в контейнере, `config/cache.lua` — кэш; кэшу на драйвере `redis`
  клиент достаётся аргументом, один пул соединений на приложение. Сами
  пакеты в контейнер не ходят.
- **Команды узла с настоящим кодом выхода.** Наполнение базы и состояние
  схемы — работа живого узла; сценарий оператора зовёт её одной функцией
  iproto и кончается тем кодом, которым команда кончилась на узле.
- **Собранное заранее.** Настройки из окружения и страницы собираются
  до подъёма узла, и ошибка шаблона видна сборке, а не первому посетителю.

## Как пользоваться

```lua
-- bootstrap/app.lua
return require('tnt.framework').new({
    name = 'demo',                      -- имя журнала и метка слоёв
    dependencies = { 'roles.httpd' },   -- роли ядра, нужные раньше
})
```

Остальное находится по соглашению от корня раскладки `base` — по умолчанию
это рабочий каталог узла, то есть каталог приложения, — и называть каждый
каталог отдельно не нужно:

| Что | Где |
|---|---|
| настройки из окружения, файл на раздел | `config/` |
| провайдеры по порядку | `bootstrap/providers.lua` |
| модели `tnt-model`, файл на модель | `app/models/` |
| шаги схемы `NNN_имя.lua` | `database/migrations/` |
| наполнители, файл на наполнитель | `database/seeders/` |
| слои HTTP, функция от контейнера | `routes/middleware.lua` |
| функции для `lua_call` | `routes/iproto.lua` |
| маршруты HTTP, по алфавиту имён | остальные `routes/*.lua` |
| переключатель режима обслуживания | `storage/framework/down`, если есть `storage/framework/` |
| страницы `<имя>.thtml.lua` | `resources/views/` |
| страницы отказов браузеру | `resources/views/errors/404.thtml.lua`, `errors/error.thtml.lua` |
| переводы, файл на язык | `lang/ru.lua`, `lang/en.lua` |
| файлы для браузера и манифест сборки | `public/`, `public/build/manifest.json` |
| собранные заранее настройки и страницы | `bootstrap/cache/config.lua`, `bootstrap/cache/views/` |

Чего на месте нет — того и нет. Явное поле объявления (`config = …`,
`routes = { … }`) перебивает соглашение; что взято по соглашению,
показывает `role.layout()` — умолчание не должно быть молчаливым:

```lua
require('bootstrap.app').layout()
--> config = 'config', providers = 'bootstrap.providers', models = { 'app.models.customer' },
--> migrations = 'database/migrations', seeders = 'database/seeders',
--> routes = { 'routes.api', 'routes.web' }, iproto = 'routes.iproto',
--> views = 'resources/views', lang = 'lang', public = 'public',
--> downtime = 'storage/framework/down'
```

Приложению, которое держит код в `src/`, корень называют — `base = 'src'`, —
и модули в нём зовутся от него: `src.routes.web`.

Все примеры этого документа — одно приложение `demo` с узлом
по такой конфигурации:

```yaml
# config.yaml
credentials:
  users:
    operator:
      password: '{{ context.operator_password }}'
      privileges:
        - permissions: [execute]
          lua_call: [demo_command]
    app:
      password: '{{ context.app_password }}'
      privileges:
        - permissions: [execute]
          lua_call: [customer_put]
        - permissions: [read, write]
          spaces: [customers]
config:
  context:
    operator_password:
      from: env
      env: OPERATOR_PASSWORD
    app_password:
      from: env
      env: APP_PASSWORD
iproto:
  listen:
    - uri: 127.0.0.1:3301
groups:
  demo:
    roles: [roles.httpd, bootstrap.app]
    roles_cfg:
      roles.httpd:
        default: { listen: 8080 }
      bootstrap.app:
        http: { server: default, url: 'https://shop.example.org', max_body: 12582912, max_file_size: 10485760, max_files: 4 }
    replicasets:
      demo:
        instances:
          demo-001: {}
```

Одна и та же роль встаёт и на роутер с сервером, и на хранилище без него:
маршруты подключаются там, где у инстанса есть `roles.httpd`, а какие
функции публиковать, `routes/iproto.lua` решает по `config.is_router`
и `config.is_storage`.

Раздел `http` роли фреймворк отдаёт ядру как есть: адрес приложения `url`,
от которого роутер собирает полные адреса, подписанные ссылки
и канонический адрес страницы, и пределы тела и формы — `max_body`,
`body_timeout`, `max_fields`, `max_parts`, `max_field_size`, `max_files`,
`max_file_size`, `in_memory`, `temp_dir`. Приложению, которое принимает
вложения больше мегабайта, их поднимают здесь же. Умолчания, проверка
и отказы — в документе [`tnt-kernel`](https://github.com/tnt-skein/tnt-kernel/blob/main/docs/kernel.md),
«Раздел `http` настроек роли». Ключ подписи ссылок в раздел не пишется —
ядро выводит его из секрета `APP_KEY` окружения.

### Приложение, которое едет роком

Раскладка ищется от `base`, а имена модулей в ней считаются от `prefix`.
Приложению в каталоге узла ни то, ни другое не нужно: корень — `.`,
и путь от него и есть имя модуля. Приложению, которое едет роком, нужны
оба: каталог находится по самому модулю, а имя модуля из пути
установленного рока не выводится.

```lua
-- acme/board.lua — модуль рока; раскладка лежит рядом, в acme/board/
local fio = require('fio')

local here = fio.dirname(debug.getinfo(1, 'S').source:sub(2))

return require('tnt.framework').new({
    name = 'acme.board',
    base = fio.pathjoin(here, 'board'), -- каталог пакета: <рок>/acme/board
    prefix = 'acme.board', -- имя модуля того же каталога
    dependencies = { 'roles.httpd' },
})
```

С ними соглашение работает как обычно: `routes/api.lua` внутри пакета —
это модуль `acme.board.routes.api`, где бы рок ни лежал, а функция
команд узла у такого приложения — `acme_board_command`:

```lua
require('acme.board').layout()
--> config = '<рок>/acme/board/config', routes = { 'acme.board.routes.api' }
```

### Маршруты и функции iproto

Маршруты и функции iproto — модулями каталога `routes/`:

```lua
-- routes/api.lua
return function(api)
    api.get('/api/customers/:id', 'customer_handlers@get', { name = 'get_customer' })
end
```

```lua
-- routes/iproto.lua
return function(app)
    local customers = app:get('customers')

    return {
        customer_put = function(id, name, age)
            local saved, err = customers.put(id, name, age)

            return saved ~= nil and saved:to_table() or nil, err
        end,
    }
end
```

```lua
-- учётка app по net.box
connection:call('customer_put', { 7, '  Пётр ', 25 })   --> { id = 7, name = 'Пётр', age = 25 }
connection:call('customer_put', { 8, 'Анна', 200 })
--> nil, 'запись customers не прошла проверку: age — должно быть целым числом от 0 до 150, а не 200'
```

```
GET /api/customers/7   → 200 {"age":25,"id":7,"name":"Пётр"}
GET /api/customers/9   → 404 {"error":"клиента нет"}
```

Функцию по `lua_call` узел исполняет с правами вызывающего: учётке `app`
выдано право на функцию и на спейс, в который та пишет.

Обработчик — функция запроса либо запись «где искать и что звать»:
`{ handlers, 'get' }` — таблица обработчиков и имя функции в ней,
`'customer_handlers@get'` — имя в контейнере и имя функции.
Обработчики зовутся точкой, без `self`: зависимости они получили при
сборке. Запись разрешается при объявлении маршрута — опечатка в имени
падает при применении конфигурации, а не на первом запросе. Помощники
ответа — `json`, `text`, `redirect` и прочие — живут у модуля
`tnt.router`, а не у экземпляра, который приходит в `routes`.

Конечная точка WebSocket маршруту отдаётся целиком —
`api.get('/ws', chat)`: так ядро видит её сессии и закрывает их,
отключая роутер.

## Провайдеры: `app/providers/` и список `bootstrap/providers.lua`

Провайдер — это части `build` и `ready` приложения, разложенные
по файлам, когда сборка перестаёт умещаться в один. Он код приложения,
а не пакета: сам пакет в контейнер не ходит — зависимость ему передают
при сборке. Каждый модуль возвращает таблицу
с `register(app, config)` и/или `ready(app, status, key)`; иное поле,
не функция или пустая таблица — ошибка при загрузке роли.

```lua
-- bootstrap/providers.lua
return {
    'app.providers.customers',
    'app.providers.pages',
}
```

```lua
-- app/providers/customers.lua
local router = require('tnt.router')

local Customer = require('app.models.customer')

return {
    register = function(app) -- объявления контейнера
        app:single('customers', function()
            return {
                put = function(id, name, age)
                    local record, err = Customer.validate({ id = id, name = name, age = age })

                    if record == nil then
                        return nil, err
                    end

                    return record:save()
                end,
                get = function(id)
                    return Customer.find(id)
                end,
            }
        end)
        app:single('customer_handlers', function(inner)
            local customers = inner:get('customers')

            return {
                get = function(request)
                    local found = customers.get(tonumber(request.params.id))

                    if found == nil then
                        return nil, { status = 404, message = 'клиента нет' }
                    end

                    return router.json(found:to_table())
                end,
            }
        end)
    end,
    ready = function(app, status) -- по box.status: сборку зовут и вне узла
        if not status.is_ro then
            app:get('log').info('клиенты принимают запись')
        end
    end,
}
```

Контейнер в приложении зовётся `app`: `app:single`, `app:value`,
`app:factory`, `app:get` — методы [`tnt-di`](https://github.com/tnt-skein/tnt-di/blob/main/docs/di.md).

Провайдер вправе принести и свои маршруты с функциями iproto: поля
`routes(api, app)` и `iproto(app)` с теми же подписями, что у приложения.
Ядро объявляет маршруты провайдеров по порядку, потом маршруты
приложения, — на одном роутере; функции iproto сливаются в один набор,
одно имя дважды — ошибка сборки. Маршруты провайдера, как и приложения,
требуют `roles.httpd` в `dependencies`.

`providers` — список имён модулей (`bootstrap/providers.lua`): порядок
задаёт список. Каталог строкой тоже принимается — тогда порядок по имени
файла (приставка `10_`, `20_`). На `apply` ядро зовёт `register`
провайдеров по порядку, потом `build` самого приложения — у него
последнее слово, объявленное провайдером он вправе подменить через
`app:replace`. На `on_event` — `ready` провайдеров по порядку, потом
`ready` приложения; каждый под своим `pcall`: сорвавшийся пишется
в журнал (`провайдер <имя> не отработал…`) и не лишает события остальных.

## Схема: каталог `database/migrations/`

Шаги схемы — файлами каталога, на `tnt-schema`: версия схемы хранится
в базе, шаги — в коде, отката нет. Файл `NNN_имя.lua` возвращает шаг —
функцию от `box`; номер в имени — версия, до которой шаг поднимает
базу:

```lua
-- database/migrations/002_statuses.lua
return function(box)
    local space = box.schema.space.create('statuses', {
        format = { { name = 'id', type = 'unsigned' }, { name = 'name', type = 'string' } },
    })
    space:create_index('primary', { parts = { { field = 'id', type = 'unsigned' } } })
end
```

Ядро регистрирует шаги при загрузке роли (файл без номера или
с негодной миграцией — ошибка), а по каждому `box.status` поднимает схему
до версии кода там, где узел вправе писать и держит данные: на ведущем
хранилище шардирования либо на ведущем узле без шардирования; роутер без
хранилища спейсов не трогает. Каждый шаг идёт в одной транзакции с записью
версии, `if_not_exists` ему не нужен. Отказ подъёма — в журнал (`схема
не поднята: …`), узел живёт дальше. Схема поднимается раньше провайдеров:
их `ready` вправе рассчитывать на спейсы.

Шаг идёт без уступки, и его предел — срез файбера: секунда, около
250 000 `replace` на 3.8, дальше ядро Tarantool рвёт работу «fiber slice
is exceeded». Долгому шагу файл возвращает не функцию, а таблицу
со срезом — той же формы, что поле `migrations` у ядра:

```lua
-- database/migrations/003_customer_ages.lua
return {
    step = function(box)
        for _, row in box.space.customers:pairs() do
            box.space.customers:replace(row:update({ { '=', 'age', math.min(row.age, 150) } }))
        end
    end,
    slice = 30,
}
```

`slice` — секунды, число больше нуля: столько `tnt-schema` даёт шагу
вместо секунды ядра (`fiber.set_slice` на время шага). Пока шаг идёт,
на узле не работает ни один другой файбер — ни репликация, ни запросы.
Шаг без среза, сорвавшийся на нём, отказывает с подсказкой задать срез
этой таблицей. Незнакомый ключ, шаг не функцией и негодный срез — ошибка
при загрузке роли с именем файла: `приложение: миграция
database/migrations/003_customer_ages.lua: slice — число больше 0,
а не 0`.

Путь — относительно рабочего каталога узла либо абсолютный; проверкам
на своём узле нужен абсолютный. Шаги отдаёт `framework.migrations(dir)`,
регистрирует их вместе со срезами ядро —
`require('tnt.kernel.schema').registered(steps)`, — поднимает
`require('tnt.schema').upgrade()`.

### Новый файл миграции: `create`

Номер нового шага считается по каталогу, а не набирается руками: два
шага с одним номером реестр не примет, а пропуск в нумерации остановит
подъём. Файл заводит `tnt.framework.migrations.create` — номер
наибольший в каталоге плюс один, три цифры, и шапка шага:

```sh
tt run -e "print(require('tnt.framework.migrations').create('orders'))"
# database/migrations/004_orders.lua
```

```lua
--- Версия 4: orders.
---
--- Шаг миграции tnt-schema: номер версии — приставка имени файла. Шаг
--- выполняется один раз, в одной транзакции с записью версии, поэтому
--- if_not_exists ему не нужен. Отката нет: следующая правка схемы —
--- следующий файл, совместимый с кодом этой версии, — а шаг обязан
--- читаться кодом прежней версии: узлы обновляются по одному.
---@param box table
return function(box)
end
```

Каталог по умолчанию — `database/migrations` от рабочего каталога,
второй аргумент называет другой; нет каталога — он заводится. Имя —
строчные латинские буквы, цифры и `_`, с буквы: оно уходит в имя файла.
Тело шага пустое, и линт приложения скажет о неиспользованном `box` —
пустой шаг не уедет в коммит незамеченным. Это команда оператора, и отказ
у неё — бросок с текстом для терминала, как у команд «Собранного
заранее»: `tt run -e` с ним кончается ненулевым кодом, а пара `nil, err`
прошла бы молча.

```
имя миграции — строчные латинские буквы, цифры и «_», с буквы, а не «add-status»
файл миграции database/migrations/004_orders.lua не заведён: fio: Permission denied
```

Файл без номера в каталоге — отказ `приложение: миграция …/orders.lua
должна начинаться с номера версии: 001_имя.lua`: номер не посчитать,
и тот же файл остановил бы узел при загрузке роли.

### Что применено: `role.migrations`

```lua
require('bootstrap.app').migrations({ format = 'text' })
```

```
узел demo-001: версия в базе 3, в коде 3
шаг  файл               состояние  применён (UTC)       узел      мс
---  -----------------  ---------  -------------------  --------  ---
1    001_customers      применён   2026-09-29 07:31:58  demo-001  1.6
2    002_statuses       применён   2026-09-29 07:31:58  demo-001  0.9
3    003_customer_ages  применён   2026-09-29 07:31:58  demo-001  0.3
```

Состояние схемы этого узла — `tnt.schema.status()`
([`tnt-schema`](https://github.com/tnt-skein/tnt-schema/blob/main/docs/schema.md),
«Что применено») с именами файлов каталога: какие шаги применены, какие
ждут, когда (UTC — узлы кластера живут в разных поясах, а сравнивать
их записи надо между собой) и каким узлом, сколько миллисекунд шёл шаг.
Состояние словом — `применён`, `ждёт`, `применён, нет в коде` (база
новее кода) и `нет в коде` (пропуск в нумерации: подъём на нём откажет).
Шаг, применённый до журнала шагов, виден применённым без времени и узла.

Ответ — таблица для кода (без `format`), текст человеку (`'text'`)
либо строка JSON другой программе (`'json'`), где время — секунды эпохи:

```json
{"instance":"demo-001","current":3,"target":3,"steps":[{"version":1,"file":"001_customers",
 "applied":true,"registered":true,"applied_at":1790667118.89,"instance":"demo-001","elapsed_ms":1.6}, …]}
```

Спрашивают узел с данными: у ведущего каждого репликасета состояние
своё, реплика показывает шаги своего лидера, а роутер, где подъёма
не было, ответит, что всё из кода ждёт. Отказ — пара `nil, err` от
`tnt.schema`; негодная настройка вызова — бросок со строкой вызывающего:
`настройки состояния схемы.format — одно из «text», «json», а не «yaml»`.

Оператор спрашивает то же командой узла `migrate:status` — текстом
человеку, с ключом `--json` строкой JSON — и получает настоящий код
выхода ([«Команды узла»](#команды-узла-dbseed-и-migratestatus)).

## Наполнители: каталог `database/seeders/`

Схему поднимают миграции, а наполнитель кладёт в неё записи: справочник
состояний, первую учётку, клиентов для разработки. Файл `<имя>.lua`
возвращает функцию от контейнера приложения либо таблицу:

```lua
-- database/seeders/statuses.lua
return function()
    for id, name in ipairs({ 'новый', 'в работе', 'готов', 'отменён' }) do
        box.space.statuses:replace({ id, name })
    end

    return 4
end
```

```lua
-- database/seeders/customers.lua
return {
    dev = true, -- только для разработки
    after = { 'statuses' }, -- кто наполняет раньше: имена файлов
    run = function(app)
        local customers = app:get('customers')

        for _, row in ipairs({ { 1, 'Мария', 46 }, { 2, 'Иван', 30 } }) do
            local ok, err = customers.put(row[1], row[2], row[3])

            if not ok then
                return nil, ('клиент %d не записан: %s'):format(row[1], tostring(err))
            end
        end

        return 2 -- сколько записей положено; можно ничего
    end,
}
```

| Поле | Что это |
|---|---|
| `run(app)` | наполняет; получает контейнер применения и отдаёт число записей, ничего либо отказ `nil, err` |
| `after` | имена наполнителей, которые наполняют раньше; по умолчанию никто |
| `dev` | только для разработки; по умолчанию `false` |

Имя наполнителя — имя файла: второго имени, которое разошлось бы
с первым, у него нет. Порядок — по `after`, а среди независимых —
по имени, и запуск не зависит от того, как `pairs` переберёт таблицу.
Незнакомый ключ, поле не того вида, зависимость, которой нет, круг
зависимостей и боевой наполнитель, ждущий наполнителя разработки, —
ошибка с именем файла:

```
приложение: наполнитель database/seeders/customers.lua: ключа «runn» нет, есть after, dev, run
приложение: наполнитель customers ждёт statuses, а такого в database/seeders нет
приложение: наполнители ждут друг друга по кругу: customers → orders → customers
приложение: наполнитель customers идёт и в production, а ждёт demo — наполнитель разработки
```

**Повтор не ломает.** Наполнитель кладёт запись заменой по ключу —
`replace`, `put` службы, `save` модели, — а не вставкой, которая
на втором запуске откажет «дубликат». Журнала выполненных наполнителей
нет намеренно: данные разработки перекладывают снова после каждой правки,
и журнал «уже наполнено» мешал бы ровно тогда, когда наполнение нужно.

### Запуск: `role.seed`

```lua
local app = require('bootstrap.app')

app.seed()                                 -- боевые наполнители; разработки — пропущены
app.seed({ dev = true })                   -- и наполнители разработки
app.seed({ only = { 'customers' } })       -- customers и те, кого он ждёт
app.seed({ dev = true, format = 'text' })  -- ответ человеку
```

```
наполнитель  записей
-----------  -------
statuses     4
customers    2
```

Наполнителю нужен контейнер применения со службами, поэтому зовут его
на живом узле — командой узла `db:seed`
([«Команды узла»](#команды-узла-dbseed-и-migratestatus)).

Каталог читается на каждом вызове: правка наполнителя видна без
перезапуска узла. Отчёт — `seeded` (кто наполнил и сколько, по порядку)
и `skipped` (наполнители разработки, которых не просили):
`app.seed()` у `demo` отдаёт `{ seeded = { { name = 'statuses', count = 4 } },
skipped = { 'customers' } }`; `format` — как у `role.migrations`. Отказы — парой:

| Отказ | Когда |
|---|---|
| `приложение demo на этом узле не применено: наполнять нечем` | роль ещё не применена — контейнера нет |
| `у приложения demo нет каталога наполнителей database/seeders` | каталога нет и в объявлении его нет |
| `наполнителя nobody нет` | в `only` имя, которого в каталоге нет |
| `наполнители разработки в среде production не запускаются` | `dev = true`, а среда — `production` |
| `наполнитель customers не выполнен: …; до него наполнили: statuses` | наполнитель отказал либо бросил; запуск стоит на нём |

Среда — `TNT_ENV` окружения приложения
([`tnt-env`](https://github.com/tnt-skein/tnt-env/blob/main/docs/env.md)):
в `production` наполнители разработки не идут даже по просьбе. Без `dev`
они не идут нигде: забытый ключ не положит данные разработки в бой.
Наполнение не транзакция, и то, что положено до отказа, остаётся; повтор
после починки безопасен — на то наполнители и кладут записи заменой.

## Команды узла: `db:seed` и `migrate:status`

Наполнение и состояние схемы — работа живого узла, и оператору нужно
позвать её из сценария и понять по коду выхода, чем кончилось. Консоль
узла для этого не годится: ответ она заворачивает в YAML, отказ
и бросок кончаются кодом 0, а строка JSON приходит строкой внутри YAML.
Поэтому роль публикует функцию iproto `<имя>_command`, которая выполняет
командную строку на [`tnt-console`](https://github.com/tnt-skein/tnt-console/blob/main/docs/console.md)
(«Команда на узле») и отдаёт итог таблицей `{ code, stdout, stderr }`,
а сценарий оператора `console.lua` зовёт её через `console.remote`
и кончается тем кодом, которым команда кончилась на узле.

```sh
$ tarantool console.lua db:seed --dev
наполнитель  записей
-----------  -------
statuses     4
customers    2
$ echo $?
0
$ tarantool console.lua db:seed --only nobody
наполнителя nobody нет
$ echo $?
1
$ tarantool console.lua migrate:status --json | jq -r .steps[0].file
001_customers
$ CONSOLE_PASSWORD=wrong tarantool console.lua migrate:status
нет ответа узла 127.0.0.1:3301: User not found or supplied credentials are invalid
$ echo $?
69
```

| Команда | Что делает |
|---|---|
| `db:seed` | `role.seed()`: боевые наполнители каталога `database/seeders` |
| `db:seed --dev` | и наполнители разработки — `dev = true` |
| `db:seed --only customers` | `customers` и те, кого он ждёт; ключ повторяется |
| `migrate:status` | `role.migrations()`: состояние схемы этого узла |
| `--json` | у обеих: ответ одной строкой JSON вместо текста |
| `--help` | справка приложения или команды |

Текст и JSON — те же, что у методов с `format`: пустые списки остаются
списками (`"skipped":[]`), время шага — секунды эпохи. Отказ метода —
код 1 и его текст в поток ошибок, неверный вызов — код 2 со строкой
вызова, бросок — код 70 со стеком. Свои коды у сценария — 69, когда
узел не ответил (нет связи, права, функции, срок вышел), и 70, когда
узел ответил не итогом команды.

**Имя функции** — имя приложения, где точка и дефис стали «_», и
`_command`: у приложения `demo` — `demo_command`, у `acme.board` —
`acme_board_command` (`lua_call` читает точку как путь по таблицам).
Функция публикуется на каждом узле приложения первой, до провайдеров,
и ядро снимает её на `stop`; провайдер или `routes/iproto.lua`, объявивший
то же имя, получит отказ `iproto: функция demo_command объявлена дважды`.

**Права.** Учётке оператора хватает права на одну функцию — строки
`operator` в `config.yaml` выше. Команда идёт от имени `admin`
(`box.session.su`): право на функцию и есть право на команды. Функцию
по `lua_call` узел исполняет с правами вызывающего, а наполнитель пишет
в спейсы приложения — права на каждый пришлось бы выдавать оператору
поимённо и держать в согласии с кодом наполнителей, и выданные они
давали бы писать туда и мимо команд. Командная строка другого
не выполнит: незнакомая команда — неверный вызов. Права на `eval` для
всего учётке не нужно, и узел ей в нём отказывает.

**Сценарий оператора** — у приложения свой, в корне: адрес, учётка
и имя функции — его настройки.

```lua
-- console.lua
local env = require('tnt.env')

require('tnt.console')
    .remote({
        uri = env('CONSOLE_URI', '127.0.0.1:3301'),
        user = env('CONSOLE_USER', 'operator'),
        password = env('CONSOLE_PASSWORD'),
        call = 'demo_command',
    })
    :main()
```

Узел и учётка — окружением, а не аргументами: аргументы целиком уходят
командой на узел, а пароль в списке процессов показываться не должен.
Окружение читает [`tnt-env`](https://github.com/tnt-skein/tnt-env/blob/main/docs/env.md):
файл `.env` рядом, поверх него окружение процесса. Один пароль у учётки
в `config.yaml` и у сценария даёт подстановка в `.env` —
`CONSOLE_PASSWORD=${OPERATOR_PASSWORD}`; на боевом узле `.env` нет,
и `CONSOLE_PASSWORD` задают окружением.

## Модели: каталог `app/models/`

Модель — файлом каталога, на [`tnt-model`](https://github.com/tnt-skein/tnt-model/blob/main/docs/model.md):
файл — модуль, возвращающий модель, и его же берут `require` службы
и обработчики. Список моделей уходит ядру, и оно привязывает их при
применении конфигурации по месту узла — на роутере через vshard,
на хранилище и одиночном узле к своим спейсам, на прослойке по net.box
в репликасет с данными — и публикует на узле с данными функции
`tnt_model_*` по этому списку. Где данные, говорит раздел `models`
настроек роли в `config.yaml` (документ `tnt-kernel`, «Модели»),
приложение об этом не знает.

```lua
-- app/models/customer.lua
local model = require('tnt.model')

return model.define({
    space = 'customers',
    fields = {
        { 'id', 'unsigned', primary = true },
        { 'name', 'string', min = 1, max = 255, trim = true },
        { 'age', 'unsigned', max = 150 },
    },
    indexes = { age = { parts = { 'age' }, unique = false } },
})
```

```lua
-- database/migrations/001_customers.lua
return require('app.models.customer').migration()
```

Шаг схемы модели каталог не регистрирует сам: он пишется файлом
миграции через `Model.migration()` — порядок версий принадлежит
приложению, а не алфавиту имён моделей. Файл каталога, вернувший
не модель, — ошибка при загрузке роли с именем модуля; пустой каталог
ядру не показывается. Явное поле `models = { Customer, Order }` перебивает
каталог.

## Настройки из окружения: каталог `config/`

Файл на раздел, умолчание рядом с именем переменной, читает `tnt.env`:

```lua
-- config/greeting.lua
return function(env)
    return {
        word = env('GREETING_WORD', 'привет'),
        retry_seconds = env('GREETING_RETRY_SECONDS', 1),
    }
end
```

Каждый файл каталога `config` возвращает функцию от окружения и отвечает
таблицей; результат лежит в `config.<имя файла>` — здесь
`app:get('config').greeting.word`. Тот же снимок лежит набором под
именем `settings` — с чтением по пути и с родом (документ `tnt-kernel`,
«Чтение по пути и с родом»):

```lua
-- в провайдере либо в build
local settings = app:get('settings')

settings:number('greeting.retry_seconds')     --> 1
settings:integer('role.bucket_count', 3000)   --> 3000: в roles_cfg не задано — умолчание
settings:string('mail.host')                  --> бросок: настройка mail.host не задана
```

Незаданный раздел так называет настройку, а не роняет провайдер отказом
Lua о поле таблицы, а строку из `{{ context.* }}` в `roles_cfg` чтение
с родом приводит само.

Окружение (`.env` и настоящие переменные) перечитывается на каждом
применении конфигурации вместе с `roles_cfg`. Незаданная обязательная
переменная (`env.required`) или значение не того рода отказывают в `validate`,
и ядро показывает это в alerts, не тронув узел; подсказки тайн журнала
ядро перед чтением дописывает в список окружения, и тайн в тексте отказа
`tnt.env` не оставляет.

Файл, вернувший не функцию, и имя, занятое ядром (`role`, `instance`,
`replicaset`, `group`, `is_router`, `is_storage`, `labels`), — ошибка
при загрузке модуля роли. Файлы каталога ничего не подключают и не
трогают `box`: они читаются до того, как узел поднят.

Файл `config/log.lua` — особый: его таблицу (`level`, `format`, `modules`)
ядро отдаёт встроенному журналу через `log.cfg` на каждом применении,
до сборки контейнера. Так журнал настраивается из `.env`; заданное здесь
перебивает раздел `log` конфигурации кластера, незаданное остаётся
из него, а карта модулей дополняется, не заменяется. `modules` — таблица
либо строка `имя=уровень` через запятую, как её пишут в `.env`
(`LOG_MODULES=tnt.router=debug,app.http=warn`). `config:reload()`
настройку не стирает: роль применяется заново. Отказ `log.cfg` — отказ
применения с именем файла.

Пароли учётных записей кластера идут не отсюда, а путём ядра Tarantool —
`{{ context.* }}` в `config.yaml`: их читает ядро при подъёме, до
всяких ролей.

## Службы по разделам настроек

Пакеты, которым нужны настройки и соединения, фреймворк собирает сам —
по файлу каталога `config/` на службу — и кладёт в контейнер под
стандартным именем:

| Раздел | Имя в контейнере | Что | Когда собирается |
|---|---|---|---|
| `config/redis.lua` | `redis` | клиент [`tnt-redis`](https://github.com/tnt-skein/tnt-redis) | первым обращением |
| `config/database.lua` с полем `driver` | `db` | драйвер [`tnt-postgres`](https://github.com/tnt-skein/tnt-postgres) либо [`tnt-mysql`](https://github.com/tnt-skein/tnt-mysql) | первым обращением |
| `config/cache.lua` | `cache` | кэш [`tnt-cache`](https://github.com/tnt-skein/tnt-cache); без раздела — в памяти | при применении |
| `config/throttle.lua` | `throttle` | ограничитель частоты [`tnt-throttle`](https://github.com/tnt-skein/tnt-throttle); без раздела — в памяти | при применении |
| `config/mail.lua` | `mail` | почта [`tnt-mail`](https://github.com/tnt-skein/tnt-mail), настроенная разделом | при применении |
| `config/files.lua` | `files` | диски [`tnt-files`](https://github.com/tnt-skein/tnt-files); у диска `s3` — клиент [`tnt-s3`](https://github.com/tnt-skein/tnt-s3) из его полей; без раздела и объявления дисков нет | при применении |
| `config/session.lua` | `session` | менеджер сессий [`tnt-session`](https://github.com/tnt-skein/tnt-session), его слой — в группе `web`, токен формы — в данных страниц; без раздела и объявления сессий нет (см. «Сессии») | при применении |

Имена служб — и константами модуля: `framework.REDIS`, `framework.DB`,
`framework.CACHE`, `framework.THROTTLE`, `framework.MAIL`, `framework.FILES`,
`framework.SESSION`; имя группы слоёв страниц — `framework.WEB`.

```lua
-- config/redis.lua
return function(env)
    return {
        host = env('REDIS_HOST', '127.0.0.1'),
        port = env('REDIS_PORT', 6379),
        password = env('REDIS_PASSWORD'),
    }
end
```

```lua
-- config/cache.lua
return function(env)
    return { driver = env('CACHE_DRIVER', 'redis'), prefix = 'demo:' }
end
```

```lua
-- config/throttle.lua
return function(env)
    return { driver = env('THROTTLE_DRIVER', 'redis') }
end
```

```lua
-- routes/web.lua: пять попыток входа в минуту с адреса
route.post('/login', function(request)
    local hits = app:get('throttle'):hit('login:' .. request.peer.host, 60)

    if hits > 5 then
        return nil, { status = 429, message = 'слишком много попыток' }
    end

    return router.json({ attempt = hits })
end)
```

```
POST /login  ×5  → 200 {"attempt":1} … {"attempt":5}
POST /login      → 429 {"error":"слишком много попыток", …}
```

**Связь — аргументом.** Кэшу и ограничителю на драйвере `redis` нужен
клиент, а клиент — не настройка: разделу его не передать. Его передаёт
фреймворк — клиент раздела `redis`, один на приложение: у кэша
и ограничителя общий пул соединений, а не по пулу на каждого. Сами
пакеты в контейнер не ходят: фреймворк зовёт `cache.new({ driver =
'redis', redis = client })` — то же, что приложение написало бы руками.
Драйвер `redis` без раздела `redis` и без клиента в объявлении — отказ
сборки, а не служба, которая откажет первым же вызовом:

```
приложение demo не собрано: приложение: cache: драйверу redis нужен клиент — раздел redis настроек либо cache.redis в объявлении
```

Свой клиент кэшу или ограничителю дают объявлением —
`cache = { driver = 'redis', redis = client }`, — а раздел настроек
дополняет его приставкой и сроком.

**База.** Раздел `database` с полем `driver` — `postgres` либо `mysql` —
заводит драйвер `db`; остальные поля раздела уходят драйверу
настройками. Под этим же именем драйвер ищет ядро для моделей
на источнике `sql` (документ `tnt-kernel`, «Модели»), и строки кода
приложению для этого не нужно:

```lua
-- config/database.lua
return function(env)
    return {
        driver = env('DB_DRIVER', 'postgres'),
        host = env('DB_HOST', '127.0.0.1'),
        port = env('DB_PORT', 5432),
        user = env('DB_USERNAME', 'app'),
        password = env('DB_PASSWORD'),
        db = env('DB_DATABASE', 'app'),
    }
end
```

```lua
app:get('db'):query('select 1 as one')   --> { { one = 1 } }
```

Раздел без `driver` — не база SQL: так пишут настройки хранения самого
Tarantool (шардирование, каталог миграций), и `db` у такого приложения
нет. Незнакомый драйвер — отказ при применении: `приложение:
database.driver — одно из «mysql», «postgres», а не «sqlite»`. Рок `pg`
либо `mysql` под драйвером — форк с починками, и ставит его приложение
рецептом из `tnt-postgres` и `tnt-mysql`; пакет драйвера грузится,
только когда раздел его назвал.

**Когда собирается.** Клиент Redis и драйвер базы — синглтоны: они
собираются первым обращением и закрываются вместе с контейнером —
на перечитывании конфигурации и останове. Узел, которому база
не понадобилась, соединений не заводит; без рока драйвера узел
применяется, а отказывает только тот, кто позвал `db`. Кэш и ограничитель
на драйвере `redis` берут клиента при сборке, так что у такого
приложения он собран сразу, — соединений он при этом не открывает, первое
откроет первая команда. Кэш, ограничитель, почта и диски собираются при
применении: их настройки проверяются сразу, и опечатка видна оператору
в alerts, а не первым запросом. Отказ несёт слово пакета и ни одного
места в исходнике: чинить надо настройку, а не строку фреймворка.

Кэш на спейсе (`CACHE_DRIVER=space`) при сборке спейса не ищет: его
заводит шаг миграции, а миграции ядро поднимает событием после
применения, — и на пустой базе первое применение проходит, а кэш находит
спейс первым обращением (документ [`tnt-cache`](https://github.com/tnt-skein/tnt-cache/blob/main/docs/cache.md),
«Драйвер space»):

```lua
-- database/migrations/005_cache.lua
return function(box)
    require('tnt.cache.space').migrate(box)      -- спейсы app_cache и app_cache_tags
end
```

**Диски.** Раздел `files` — те же настройки, что у `files.new`
([`tnt-files`](https://github.com/tnt-skein/tnt-files/blob/main/docs/files.md)):
`default` и `disks` по именам. Диску `s3` без своего клиента фреймворк
собирает клиент `tnt-s3` из полей диска: поля самого диска — `driver`,
`prefix`, `url` — остаются диску, а всё прочее — `endpoint`, `bucket`,
ключи, срок — уходит клиенту. Пакет `tnt-s3` грузится, только когда
такой диск назван. Клиент в сеть не ходит, пока его не позвали, а его
настройки проверяются при применении: без ключей в окружении приложение
не применится.

```
приложение demo не собрано: настройки s3.access_key — непустая строка, а не nil
```

```lua
-- config/files.lua
return function(env)
    return {
        default = 'local',
        disks = {
            ['local'] = { driver = 'local', root = env('FILES_ROOT', 'storage/app'), url = '/storage' },
            s3 = {
                driver = 's3',
                prefix = 'uploads/',
                url = 'https://cdn.example.org',
                endpoint = env('S3_ENDPOINT', 'http://127.0.0.1:19000'),
                bucket = 'tnt-live',
                access_key = env('S3_ACCESS_KEY'),
                secret_key = env('S3_SECRET_KEY'),
            },
        },
    }
end
```

```lua
-- в службе приложения
app:get('files'):disk():put('a/b.txt', 'данные')    --> true
app:get('files'):disk():url('a/b.txt')              --> /storage/a/b.txt
```

Раздел сливается с объявлением по дискам, а не целиком: то, что
в раздел не положить, — функцию подписи `sign` локального диска, свой
клиент ведра, — даёт объявление `files = { disks = { … } }`, а каталог,
адрес и ключи — раздел. Свой клиент в объявлении и поля клиента в разделе
у одного диска вместе — отказ сборки с именем поля: брать одно из двух
молча нельзя. Без раздела и без объявления дисков нет — каталог
по умолчанию завёл бы файлы там, где их никто не ждёт; `files = false`
выключает диски и при разделе.

**Почта** настраивается на процесс: настройки у `tnt-mail` общие
(`mail.configure`), и фреймворк отдаёт ему раздел на каждом применении,
а в контейнер кладёт сам пакет — службы зовут
`app:get('mail').send(letter)`, проверки подменяют его `app:replace`.
Без раздела `mail` фреймворк почту не трогает: её вправе настроить само
приложение. Два приложения с разделом `mail` в одном процессе
перебивают друг друга — действует применённое последним.

**Подмена.** Службы объявляются до провайдеров, и провайдер вправе
заменить любую через `app:replace` — у сборки приложения последнее
слово. Клиента Redis, которого кэш или ограничитель уже взяли при
сборке, подменять поздно: свой клиент им дают объявлением.
`throttle = false` выключает ограничитель, как `cache = false` — кэш.
Вне узла служб нет (см. «Собранное заранее»).

## Сессии: раздел `session` и группа `web`

Сессии объявляются настройкой. Файл `config/session.lua` — и у приложения
есть менеджер [`tnt-session`](https://github.com/tnt-skein/tnt-session/blob/main/docs/session.md)
в контейнере под именем `session`, а его слой — в реестре слоёв
приложения и в группе `web`, которую маршрут страницы берёт именем:

```lua
-- config/session.lua
return function(env)
    return {
        driver = env('SESSION_DRIVER', 'cache'), -- cache либо cookie
        name = env('SESSION_COOKIE', 'demo_session'), -- имя куки
        lifetime = env('SESSION_LIFETIME', 7200), -- секунды
        cookie = { secure = env.bool('SESSION_SECURE_COOKIE', true) },
    }
end
```

```lua
-- routes/web.lua
route.get('/visits', function(request)
    local visits = (request.session:get('visits') or 0) + 1

    request.session:put('visits', visits)

    return router.text(tostring(visits))
end, { middleware = { 'web' } })

-- API идёт мимо группы: ни сессии, ни куки.
route.get('/api/items', function(request)
    return router.json({ session = request.session ~= nil })
end)
```

```
GET /visits                                  → 1
    set-cookie: demo_session=vZ5a9WJyhsO7XRxz6XQkw20e7aCBHjkCXrKmnW-a0bk; Max-Age=7200; Path=/; SameSite=Lax; Secure; HttpOnly
GET /visits    cookie: demo_session=vZ5a9…   → 2
GET /api/items cookie: demo_session=vZ5a9…   → {"session":false}, без set-cookie
```

Одно место на все приложения — одно имя куки из раздела, один срок и одно
место слоя в цепочке: под стражем у найденного маршрута, до его обработчика.
Имя группы — и константой `framework.WEB`. Слой стоит в реестре под
именем `session`, фабрикой менеджера (`sessions:factory()`), и маршрут
вправе взять его и сам, с настройками: `{ 'session', { field = 'visitor' } }`.
Группа маршрутов берёт группу тем же полем:
`route.group('/account', { middleware = { 'web' } }, function(r) … end)`.

**Что где пишется.** Раздел несёт то, что пишется строкой и числом;
хранилище и шифровальщик — не настройки, и в раздел их не положить, их дают
объявлением приложения:

| Где | Что |
|---|---|
| раздел `config/session.lua` | `driver`, `name`, `lifetime`, `cookie` — настройки `session.new` (документ `tnt-session`, «Настройки») |
| объявление `session = { … }` | то же, и сверх того `cache` — хранилище `tnt-cache` либо функция от контейнера, `cipher` — шифровальщик `tnt-crypto` |

Раздел главнее объявления, а настройки куки сливаются по полю, а не
целиком: домен куки даёт объявление, `secure = false` стенда без TLS —
раздел из окружения, и одно не затирает другое. Незнакомое поле — отказ:
`tnt-session` лишних полей не разбирает, и `lifetme = 60` молча оставило бы
сессию на два часа. Поле объявления проверяется при загрузке роли, поле
раздела — при применении; шифровальщик, попавший в раздел, — такое же
незнакомое поле:

```
приложение: session: ключа «lifetme» нет, есть cache, cipher, cookie, driver, lifetime, name
приложение demo не собрано: приложение: раздел session: ключа «cipher» нет, есть cookie, driver, lifetime, name
```

**Хранилище.** Драйверу `cache` без своего хранилища достаётся кэш
приложения — служба `cache`: `CACHE_DRIVER=redis` уводит в Redis и кэш,
и сессии, одним клиентом. Общее хранилище значит и общий `flush`:
`app:get('cache'):flush()` разлогинит всех. Кому это не годится — своё
хранилище объявлением. Хранилищу, которому нужно что-то из контейнера, —
клиент Redis приложения, — объявление даёт функцию от контейнера: она
зовётся при применении, а при загрузке роли клиента ещё нет.
Так сделано у `demo`:

```lua
-- bootstrap/app.lua
local cache = require('tnt.cache')

return require('tnt.framework').new({
    name = 'demo',
    dependencies = { 'roles.httpd' },
    -- Сессии в Redis отдельно от кэша: клиент приложения, своё
    -- пространство ключей — `flush` кэша их не заденет.
    session = {
        cache = function(app)
            return cache.new({ driver = 'redis', redis = app:get('redis'), namespace = 'session:' })
        end,
    },
    cors = {
        origins = { 'https://app.example.org' },
        methods = { 'PUT', 'PATCH', 'DELETE' },
        headers = { 'content-type', 'authorization' },
        max_age = 600,
        path = '/api', -- /api и всё под ним; без path — все пути
    },
})
```

```
GET /visits → 1, кука demo_session=vZ5a9…
EXISTS session:vZ5a9WJyhsO7XRxz6XQkw20e7aCBHjkCXrKmnW-a0bk   --> 1
```

Сессии в спейсе — хранилищем кэша на своём спейсе (документ
`tnt-session`, «Сессия в спейсе»), и функция для него не нужна: спейс
по имени хранилище ищет первым обращением, а не при сборке (документ
`tnt-cache`, «Драйвер space»), и заводят его прямо в объявлении, при
загрузке роли. Спейс заводит шаг миграции, а миграции ядро поднимает
после применения роли: на пустой базе первое применение проходит, шаг
идёт следом, и сессии пишутся в спейс, который он завёл.

```lua
-- bootstrap/app.lua
local cache = require('tnt.cache')

return require('tnt.framework').new({
    name = 'demo',
    dependencies = { 'roles.httpd' },
    session = {
        cache = cache.new({ driver = 'space', space = 'app_sessions', prefix = 'sess:' }),
    },
})

-- database/migrations/006_sessions.lua
return function(box)
    require('tnt.cache.space').migrate(box, 'app_sessions')
end
```

Кэш приложения выключен (`cache = false`), а своего хранилища объявление
не дало — отказ сборки, а не сессия, которая откажет первым же запросом.
Драйверу `cookie` хранилище не нужно, ему нужен шифровальщик — тоже
объявлением, `session = { cipher = crypto.new({ key = crypto.derive(secret,
'session') }) }`; без него отказывает сам `tnt-session`:

```
приложение demo не собрано: приложение: session: драйверу cache нужно хранилище — кэш приложения либо session.cache в объявлении
приложение demo не собрано: сессия: драйверу cookie нужен шифровальщик tnt-crypto аргументом cipher
```

**Без раздела и без объявления сессий нет** — ни менеджера в контейнере,
ни слоя в реестре: сессия — это кука у каждого посетителя, и ставить её
приложению, которое о ней не просило, нельзя. Одного объявления хватает
и без раздела. `session = false` выключает сессии и при разделе. Группа
`web` при этом есть, пустая: маршрут страницы объявляется одинаково при
любом разделе, и выключенные сессии не роняют сборку. Маршрут, назвавший
сам слой `session`, без сессий не собирается: `слой или группа «session»
не объявлены`.

**Когда собирается.** Менеджер — при применении, после служб: настройки
проверяются сразу, и опечатка видна оператору в alerts. Кэш приложения он
берёт тогда же, и подменять кэш провайдером после этого поздно — своё
хранилище сессиям дают объявлением. Слой собирается позже, вместе
с роутером, после провайдеров и `build`: менеджер, подменённый ими через
`app:replace('session', …)`, и встанет в слой. Вне узла сессий нет, как и
служб.

Сверку токена от подделки запроса (`csrf`) фреймворк в группу сам
не ставит: какие адреса от неё освободить, решает приложение. Оно кладёт
её в свою группу `web`, и она встаёт после слоя сессий (см. «Свои слои
и группы»; документ `tnt-session`, «Защита форм от подделки запроса»).

**Токен формы кладётся в страницы сам.** При сессиях у роутера
приложения есть общие данные страниц: токен сессии полем `csrf_token` —
его ждут директивы `@csrf` и `@csrf_meta`
([`tnt-template`](https://github.com/tnt-skein/tnt-template/blob/main/docs/template.md),
«Токен формы»). Обработчик формы о токене не знает, и форма, забытая
в одном из двадцати обработчиков, не падает у посетителя ответом 500:

```lua
-- bootstrap/app.lua
local session = require('tnt.session')

return require('tnt.framework').new({
    name = 'demo',
    dependencies = { 'roles.httpd' },
    -- Сверка токена — в группу web, за слоем сессий.
    groups = { web = { session.csrf.new() } },
})
```

```lua
-- routes/web.lua
local router = require('tnt.router')

return function(route)
    route.get('/customers/new', function()
        return route.view('customers.form', { name = 'Иван' })   -- токен не назван
    end, { middleware = { 'web' } })

    route.post('/customers', function(request)
        return router.text('принято: ' .. request.form.name)
    end, { middleware = { 'web' } })
end
```

```html
<!-- resources/views/customers/form.thtml.lua -->
<form method="post" action="/customers">
    @csrf
    <input name="name" value="{{ name }}">
</form>
```

```
GET  /customers/new                                     → 200, <input type="hidden" name="_token" value="3lVL…">
POST /customers  cookie: demo_session=…  _token=3lVL…   → 200, принято: Anna
POST /customers  cookie: demo_session=…  без _token     → 403
```

Токен кладётся, только когда сессия в запросе есть — в поле `session`,
куда её кладёт слой. Маршрут API идёт мимо группы `web`, и его странице
достаются пустые общие данные, а не бросок; `@csrf` на ней падает при
рисовании, как и без сессий. Токен заводится первым показом страницы
группы `web` — любой, а не только с формой: сессия с токеном
сохраняется, и новому посетителю уходит кука. Слою, которому маршрут
назвал другое поле (`{ 'session', { field = 'visitor' } }`), токен
в страницу не приходит — его кладёт приложение своими общими данными.

**Свои общие данные** приложение даёт полем `view_data`: функция
от контейнера отдаёт функцию от запроса, а та — таблицу.

```lua
-- bootstrap/app.lua
return require('tnt.framework').new({
    name = 'demo',
    dependencies = { 'roles.httpd' },
    view_data = function(app)
        local instance = app:get('config').instance

        return function(request)
            return { instance = instance, visitor = request.session and request.session:get('user') }
        end
    end,
})
```

Данные приложения главнее встроенных — своё `csrf_token` перебивает
токен сессии, — а данные обработчика главнее обоих. Функция приложения
зовётся первой: её отказ парой `nil, err` становится ответом по договору
отказа, и токен сессии до такого ответа не заводится. Пусто и не
таблица — поломка словом роутера, не функция от запроса — отказ сборки:

```
приложение demo не собрано: приложение: view_data должна отдать функцию от запроса, получено table
```

## Свои слои и группы: `layers` и `groups`

Реестр слоёв у приложения свой (документ `tnt-kernel`, «Свои слои
и группы»), и фреймворк кладёт в него слой сессий. Свои слои и группы
приложение объявляет там же — полями `layers` и `groups`, таблицей либо
функцией от контейнера, когда слою нужна служба приложения. Маршрут
и группа маршрутов берут их по имени:

```lua
-- bootstrap/app.lua
local session = require('tnt.session')

-- Сессии — разделом config/session.lua (см. «Сессии»).
return require('tnt.framework').new({
    name = 'demo',
    dependencies = { 'roles.httpd' },
    -- Ограничителю нужна служба из контейнера — слои функцией от него.
    layers = function(app)
        return { throttle = app:get('throttle'):factory() }
    end,
    groups = {
        -- Сверка токена — в группу web: она встанет после слоя сессий.
        web = { session.csrf.new({ except = { '/hooks' } }) },
        api = { { 'throttle', { per_minute = 60 } } },
    },
})
```

```lua
-- routes/web.lua
return function(route)
    route.get('/form', form, { middleware = { 'web' } })
    route.post('/form', save, { middleware = { 'web' } })
    route.post('/hooks/pay', paid, { middleware = { 'web' } })
    route.get('/api/items', items, { middleware = { 'api' } })
end
```

```
POST /form                                            → 403 {"error":"запрос не подтверждён токеном"}
POST /form   cookie: demo_session=…, x-csrf-token: …  → 200
POST /hooks/pay                                       → 200, без сверки
GET /api/items, 61-й запрос за минуту                 → 429, retry-after: 60
```

**Группа `web` — слой сессий, за ним записи приложения.** Здесь она
`{ 'session', сверка }`: сверка берёт сессию из запроса, и порядок
«сессия, потом сверка» задан одним правилом, а не заботой каждого
маршрута. Без сессий группа `web` — одни записи приложения; сверка без
слоя сессий бросает на первом же `POST` — ответ 500, а в журнале
`сверка токена: в запросе нет поля «session» — слой csrf ставят после
слоя session`. Слой, которому место до сессии, ставят своей группой
вокруг `web`: `page = { { 'throttle', { per_minute = 60 } }, 'web' }` —
запрос сверх предела не дойдёт до хранилища сессий. Объявление
приложения при этом не меняется: слой сессий встаёт в копию группы,
и следующее применение не допишет его второй раз.

**Имя `session` — за фреймворком.** Свой слой под этим именем — отказ
сборки, есть сессии или нет: включённые разделом, они молча подменили бы
слой приложения. Менеджер сессий подменяют иначе —
`app:replace('session', …)` в `build` либо в провайдере. Группа `web`,
назвавшая слой сессий сама, именем либо записью `{ 'session', … }`, —
тоже отказ: второй слой в ней вёл бы вторую сессию того же запроса.
Своя группа вправе взять слой сессий именем и поставить его, где ей
нужно.

```
приложение demo не собрано: приложение: слой session ставит фреймворк — свой слой назовите иначе, а менеджер сессий подменяют через app:replace('session', …)
приложение demo не собрано: приложение: группа web: слой session фреймворк ставит в неё сам, первым, — назовите в ней только свои слои
```

**Когда проверяется.** Вид поля — таблица либо функция — при загрузке
роли: ядру уходит функция фреймворка, и поля приложения ядро не увидит.
Что отдала функция и имя `session` — при сборке, на применении:
контейнера раньше нет. Не таблицу слоёв или групп и группу не списком
отвергает реестр `tnt-middleware` своим словом (`группа «web»
объявляется списком записей, а не string`), имена слоёв входа ядра —
`request_id_header`, `request_id`, `trace`, `log` — ядро
(документ `tnt-kernel`):

```
приложение: layers должно быть table или function, получено string
```

Слои собираются вместе с роутером, после провайдеров и `build`: служба,
подменённая ими через `app:replace`, и встанет в слой.

## Режим обслуживания: `storage/framework/down`

Файл на месте — приложение отвечает 503 на всё, кроме путей `except`
и запросов с кукой обхода по тайне
([`tnt-downtime`](https://github.com/tnt-skein/tnt-downtime/blob/main/docs/downtime.md)).
Слой стоит на входе роутера, до поиска маршрута, под слоем межсайтовых
запросов (см. «Межсайтовые запросы»); сам режим лежит в контейнере под
именем `downtime`, и провайдеры вправе на него положиться:

```lua
app:get('downtime'):down({ message = 'выкатываем 2.0', retry = 120, secret = 'k7z4m' })
app:get('downtime'):up()
```

```
GET /about   → 503 {"error":"выкатываем 2.0"}, retry-after: 120
GET /health  → мимо режима: путь в except
```

Настраивается разделом `app.maintenance` из `config/app.lua`:

```lua
-- config/app.lua
return function(env)
    return {
        name = env('APP_NAME', 'demo'),
        locale = env('APP_LOCALE', 'ru'),
        maintenance = {
            driver = env('APP_MAINTENANCE_DRIVER', 'file'), -- драйвер пока один
            path = env('APP_MAINTENANCE_PATH'), -- пусто — storage/framework/down
            except = { '/health' },
        },
        cors = env.bool('CORS_ENABLED', true) and {
            origins = env.list('CORS_ALLOWED_ORIGINS'), -- через запятую; не задано — из объявления
        } or false,
        assets = {
            build = env('APP_ASSETS_BUILD', 'build'), -- каталог сборки внутри public
            watch = env.bool('APP_ASSETS_WATCH', false), -- перечитывать по времени правки
        },
    }
end
```

Раздел главнее объявления, объявление — соглашения; `downtime = false`
выключает режим вовсе. Драйвер, кроме `file`, — ошибка сборки, а не
молча не включившийся режим.

## Межсайтовые запросы: поле `cors` и раздел `app.cors`

Сценарий страницы с другого сайта — клиент API на своём домене, панель
партнёра — читает ответы приложения только с его разрешения. Разрешение
выдаёт слой `cors` ([`tnt-middleware`](https://github.com/tnt-skein/tnt-middleware/blob/main/docs/middleware.md),
«Межсайтовые запросы: `cors`»), а ставит его фреймворк: поле `cors`
объявления — те же настройки, что у слоя, и сверх них начало пути `path`.
У `demo` оно стоит в `bootstrap/app.lua` выше:

```lua
cors = {
    origins = { 'https://app.example.org' },
    methods = { 'PUT', 'PATCH', 'DELETE' },
    headers = { 'content-type', 'authorization' },
    max_age = 600,
    path = '/api', -- /api и всё под ним; без path — все пути
},
```

```
OPTIONS /api/customers/7   origin: https://app.example.org, access-control-request-method: PUT
  → 204  access-control-allow-origin: https://app.example.org
         access-control-allow-methods: PUT, PATCH, DELETE
         access-control-allow-headers: content-type, authorization
         access-control-max-age: 600, vary: Origin               — обработчик не звался
OPTIONS /api/customers/7   origin: https://evil.example.com, access-control-request-method: PUT
  → 403  {"error":"источник запроса не разрешён", …}, vary: Origin
GET /api/customers/7       origin: https://app.example.org
  → 200  access-control-allow-origin: https://app.example.org, vary: Origin
```

**Где стоит слой.** Первым на входе роутера, до поиска маршрута. Среди
слоёв приложения (`middleware`) он предварительного запроса не увидел бы:
на `OPTIONS` к существующему пути роутер отвечает сам — 204 с `Allow`
и без разрешений, — и браузер отверг бы всякий запрос сложнее простого.
Выше режима обслуживания — затем, чтобы 503 закрытого приложения тоже
нёс разрешение: сценарий прочтёт слово и срок повтора, а не сетевую
ошибку. Предварительный запрос закрытому приложению отвечает слой, а 503
получает уже сам запрос. Разрешение несут и промах по адресу, и отказы
обработчиков. Имя слоя на входе — `cors`, и константой `framework.CORS`.

**Раздел `app.cors`** — те же поля в `config/app.lua` (он выше, у режима
обслуживания), и он главнее объявления по полю: источники у стенда и боя
свои, их задаёт окружение без правки кода, а способы и заголовки API
остаются в объявлении рядом с кодом:

```
CORS_ALLOWED_ORIGINS=https://admin.example.org, https://*.example.net
OPTIONS /api/customers/7   origin: https://admin.example.org  → 204, access-control-allow-methods: PUT, PATCH, DELETE
OPTIONS /api/customers/7   origin: https://app.example.org    → 403: источник объявления перебит разделом
```

Незаданная переменная даёт пусто, и поле остаётся из объявления: раздел
не стирает его пустотой. Список из раздела заменяет список объявления
целиком, а не дополняет его. `false` в разделе выключает слой,
объявленный в коде, — `CORS_ENABLED=false` выше. Слой собирается заново
на каждом применении, и `config:reload()` подхватывает правку раздела.

**Без объявления и без раздела слоя нет**: разрешение читать ответы
чужим страницам выдаётся только по просьбе. Одного раздела хватает и без
объявления; `cors = false` в объявлении выключает слой и при разделе.

**Отказы.** Вид поля и незнакомое имя в объявлении — отказ при загрузке
роли, в разделе — при применении. Сами настройки слоя проверяются при
применении, когда источники уже пришли разделом, — словом слоя и без
места в исходнике: чинить надо настройку, а не строку фреймворка.

```
приложение: cors: ключа «orgins» нет, есть credentials, expose, headers, max_age, methods, origins, path
приложение demo не собрано: приложение: app.cors должно быть table или false, получено string
приложение demo не собрано: настройки слоя cors.origins — массив, а не nil
приложение demo не собрано: настройки слоя cors: источник «*» вместе с credentials браузер отвергает, …
```

## Страницы: `resources/views/`

Страница — файл `<имя>.thtml.lua` с `{{ }}`, `@if`, `@for`, `@extends`
([`tnt-template`](https://github.com/tnt-skein/tnt-template/blob/main/docs/template.md)).
Движок — `app:get('view')`, свой директивы заводит провайдер:

```lua
-- app/providers/pages.lua: свои директивы
return {
    register = function(app)
        app:get('view'):directive('date', function(at)
            return os.date('!%d.%m.%Y', at)
        end)
    end,
}
```

```html
{{-- resources/views/layouts/app.thtml.lua --}}
<!doctype html>
<html lang="@locale()">
<head>
<title>@lang('home.title')</title>
<link rel="stylesheet" href="@asset('resources/css/app.scss')">
@canonical(canonical)
</head>
<body>@yield('page')</body>
</html>
```

```html
{{-- resources/views/about.thtml.lua --}}
@extends('layouts.app')

@section('page')
<p>Узел {{ instance }}, поднят @date(started_at).</p>
<p>@choice('nodes', 3)</p>
@endsection
```

```lua
-- routes/web.lua
route.get('/about', function()
    return route.view('about', { instance = app:get('config').instance, started_at = 0 })
end)
```

```
GET /about                     → <html lang="ru"> … <title>Главная</title> … <p>Узел demo-001, поднят 01.01.1970.</p> <p>3 узла</p>
GET /about  accept-language: en → <html lang="en"> … <title>Home</title> … <p>3 nodes</p>, content-language: en
```

### Канонический адрес: `@canonical`

Одну страницу открывают по многим адресам — с меткой рассылки,
с порядком сортировки, по второму имени узла, — и `<link rel="canonical">`
называет поисковику один. Адрес собирает роутер приложения от `http.url`
и кладёт в данные страницы, а директива `@canonical` в рамке сайта пишет
по нему тег — рамка `demo` выше уже его ставит:

```lua
-- routes/web.lua
route.get('/articles/:slug', function(request)
    return route.view('article', {
        slug = request.params.slug,
        canonical = route.canonical(request, { query = { 'page' } }),
    })
end)
```

```
GET /articles/%d0%bf?page=2&utm_source=mail
--> <link rel="canonical" href="https://shop.example.org/articles/%D0%BF?page=2">
```

Метка рассылки отброшена, названное поле осталось; `&` между полями
в значении атрибута пишется `&amp;`. Рамка одна на все страницы, а адрес
есть не у каждой: страница без него не получает ничего, а не `href=""` —
пустой адрес поисковик прочёл бы адресом самой страницы, со всеми
метками рассылки. Адрес не строкой — бросок с именем шаблона и строкой
в нём: `about:2: @canonical ждёт адрес строкой, а не number`.

Директиву заводит фреймворк у всякого движка страниц, до провайдеров,
и имя `canonical` у движка приложения занято: своя директива с ним —
отказ `шаблоны: директива @canonical уже есть`. Тег она пишет как есть,
директивой разметки `tnt-template` («Своя разметка»): ответ обычной
директивы экранируется, и тег вышел бы текстом.

### Показ значения: `@dump`

Тому, кто собирает страницу, нужно видеть данные, которые в неё пришли,
там же, где они рисуются: журнал узла лежит на другой машине, а страница
уже открыта. Директива `@dump` пишет значение показом `describe` пакета
[`tnt-debug`](https://github.com/tnt-skein/tnt-debug/blob/main/docs/debug.md):

```lua
-- routes/web.lua
route.get('/customer', function()
    return route.view('customer', {
        customer = { name = 'Иван <Петров>', city = 'Казань', password = 'hunter2' },
    })
end)
```

```html
{{-- resources/views/customer.thtml.lua --}}
<pre>@dump(customer)</pre>
```

```
GET /customer
--> <pre>{
-->     city = &quot;Казань&quot;,
-->     name = &quot;Иван &lt;Петров&gt;&quot;,
-->     password = [скрыто]
--> }</pre>
```

Ключи идут в постоянном порядке, кириллица — как есть, род значения
виден (`uuid("…")`, `1LL`, `tuple { … }`), значение под именем-тайной
(`password`, `token`, `api_key`, …) — `[скрыто]`, пределы показа
по умолчанию держатся (8 уровней, 100 пар, 200 байт строки), и броска
нет ни на каком значении: страница не падает оттого, что на неё смотрят.
Настроек у директивы нет — всё, что стоит в скобках, показывается.

Ответ экранируется, как всякий вывод: кавычки показа уходят `&quot;`,
а строка из данных с `<script>` выходит текстом. Показ многострочный,
и переводы строк сохраняет `<pre>` вокруг директивы. Значений несколько —
каждое своим показом, через запятую с переводом строки, как `dump`
пишет их одной записью журнала: `@dump(order, total)`. `nil` показывается
словом `nil`, `@dump()` без значений — пусто.

Директиву заводит фреймворк у всякого движка страниц, до провайдеров, как
и `@canonical`: своя директива с именем `dump` — отказ сборки
`приложение demo не собрано: шаблоны: директива @dump уже есть`. Страницу
с `@dump` видит каждый её посетитель — см. «Чем пришлось поступиться».

### Страницы отказов: `resources/views/errors/`

Человек, попавший на несуществующий адрес, должен увидеть сайт,
а не голое тело отказа. Страницы отказов — обычные шаблоны и живут там
же, где остальные:

```
resources/views/errors/404.thtml.lua     страница на свой код ответа
resources/views/errors/error.thtml.lua   общая на все остальные
```

Объявлять их не нужно — каталог находится по соглашению, — а получает
их каталог отказов ядра. Браузеру, попросившему `text/html`, отказ
уходит страницей; сценарию — прежним телом (документ
[`tnt-error`](https://github.com/tnt-skein/tnt-error/blob/main/docs/error.md),
«Страница браузеру»). Шаблон ищется по коду ответа, а чего нет — общим
`errors/error`; нет ни своего, ни общего — рисует встроенная страница
`tnt-error`.

Данные страницы приходят от каталога отказов: `status`, `title`
(заголовок по коду), `message` (слово отказа), `incident` и `request_id`
— номера, по которым происшествие находят в журнале.

```html
{{-- resources/views/errors/404.thtml.lua --}}
@extends('layouts.app')

@section('page')
<h1>Страницы нет</h1>
<p>{{ message }}. Номер происшествия — {{ incident }}.</p>
@endsection
```

```
GET /нет  accept: text/html   → 404 … <h1>Страницы нет</h1> <p>нет такого адреса. Номер происшествия — PETV-W46J.</p>
GET /нет                      → 404 {"error":"нет такого адреса","incident":"…"}
```

Рамка сайта — обычное наследование: страница отказа стоит на той же
рамке, что и остальные, и отдельный слой рамки под страницами отказов
вправе дописать под текстом оба номера — тогда их не забудут ровно там,
где они нужнее всего.

Каталог читается один раз, при сборке приложения: чтение каталога
на каждый промах по адресу — это работа с диском там, где узел уже
отвечает отказом. Правка страницы при этом не теряется — движок
и список свои на каждое применение, и `config:reload()` перечитывает
оба.

Подробностей поломки шаблон приложения не получает никогда: место
в коде, стек и заголовки запроса показывает страница разбора, которую
`tnt-error` рисует сам и только по настройке `http.debug` ядра.

## Переводы: `lang/`

Строки для человека на нескольких языках — файлом на язык в `lang/`.
Файл — данные Lua, а не модуль: его читает `tnt-config` без глобалов
и без байт-кода, так что строка перевода кода не исполняет. Имя файла —
метка языка по форме: `ru.lua`, `en-GB.lua`.

```lua
-- lang/ru.lua
return {
    home = { title = 'Главная' },
    nodes = { '{count} узел', '{count} узла', '{count} узлов' },
}
```

```lua
-- lang/en.lua
return {
    home = { title = 'Home' },
    nodes = { '{count} node', '{count} nodes' },
    errors = {
        ['404'] = 'No such address', -- промах по адресу
        internal = 'Something broke. Tell {incident} to whoever looks into it.',
    },
}
```

Язык по умолчанию — настройка `app.locale` (`config/app.lua` выше). При
одном файле язык по умолчанию — он сам; при нескольких без настройки
сборка отказывает: выбрать язык за приложение по алфавиту значило бы
однажды заговорить с посетителем по-английски только потому, что
кто-то добавил `de.lua`.

```
приложение demo не собрано: приложение: переводы: в lang языков несколько (en, ru) — назовите язык по умолчанию настройкой app.locale
```

Из каталога собирается переводчик [`tnt-i18n`](https://github.com/tnt-skein/tnt-i18n/blob/main/docs/i18n.md),
и приложение получает четыре вещи:

- переводчик в контейнере под именем `i18n`: `app:get('i18n'):get('home.title')`;
- директивы страниц — `@lang('home.title')`, `@choice('nodes', count)`
  и `@locale()` — они стоят в рамке и странице `demo` выше;
- слой `locale` на входе роутера, после режима обслуживания: язык
  запроса по `Accept-Language` ложится в контекст на весь запрос,
  а ответу ставятся `Content-Language` и `Vary: Accept-Language`.
  Строки обработчика и страницы говорят на языке запроса без аргумента;
- слово отказа на языке запроса — строкой раздела `errors`
  («Слова отказов» ниже).

Негодный файл — код вместо данных, пустой, список — и негодные строки —
три формы у английского, язык без правила множественного числа — отказ
сборки со словом `tnt-i18n`, а не страница с дырой на первом запросе.
Каталог перечитывается на каждом применении, как и страницы.

Языку, которого среди встроенных правил нет (`ru`, `uk`, `be`, `en`),
правило множественного числа задают сами — подменой переводчика в `build`:
директивы страниц и слой берут его из контейнера на каждом вызове.

```lua
build = function(app)
    app:replace('i18n', i18n.new({ locale = 'fr', messages = …, plurals = { fr = rule } }))
end
```

`lang = false` выключает переводы при каталоге на месте; пустой каталог —
переводов нет.

### Слова отказов

Отказ говорит на языке запроса так же, как страница: его слово лежит
строкой раздела `errors` (`lang/en.lua` выше). Ключ — код отказа,
а у отказа без кода — статус ответа: 404 и 405 роутер собирает сам, кода
у них нет, и слово «нет такого адреса» сказано по статусу. Отказ со своим
кодом — `order.unfit` — ищется строкой `errors.order.unfit`.

```
GET /нет  accept-language: en  → 404 {"error":"No such address","incident":…}
                                 content-language: en, vary: Accept-Language
GET /нет  (без заголовка)      → 404 {"error":"нет такого адреса","incident":…}
```

Подстановки слова — подстановки отказа и `{incident}`, опознаватель
происшествия; слово внутренней поломки без него не берётся (документ
`tnt-error`, «Слово на языке запроса»). Строки нет ни в языке
запроса, ни в языке по умолчанию — уходит слово самого отказа, а не
ключ, как на странице: ключ ушёл бы клиенту в теле. Строка языка
по умолчанию, напротив, годится и посетителю на другом языке: её
написало приложение, и она главнее слова пакета. По статусу ищется
только отказ без кода: у отказа с кодом общая строка о статусе сказала
бы меньше его собственного слова. Слово, сказанное `explain`,
не переводится вовсе.

Слово то же в теле и на странице отказа, а страница приложения
(`resources/views/errors`) рисуется в области языка и говорит
директивами `@lang` на нём же. Встроенная страница `tnt-error` переводит
одно слово: заголовок по коду и подписи у неё по-русски.

Отказ режима обслуживания говорит на языке по умолчанию: его слой стоит
выше слоя языка — закрытое приложение не пускает к запросу ни одного
своего слоя, — и языка запроса он не узнаёт.

## Файлы для браузера: `public/` и помощник `asset`

В `public/` лежит то, что уходит браузеру как есть: собранные стили
и сценарии, шрифты, картинки, `favicon.ico`. Каталог находится
соглашением и записывается в раскладку:

```lua
local layout = require('tnt.framework.layout')
local declared, found = layout.by_convention({ name = 'demo' })
-- found.public == 'public'
```

Раздаёт файлы роутер, и объявляет раздачу приложение — там же, где
объявляет маршруты (документ [`tnt-router`](https://github.com/tnt-skein/tnt-router/blob/main/docs/router.md),
«Раздача файлов»):

```lua
-- routes/web.lua
return function(route, app)
    -- Каталог сборки: у файлов отпечаток в имени, им можно дать год кэша.
    route.serve('/build', 'public/build', { immutable = true })
    …
end
```

```
GET /build/assets/app-BX7Yy2Qk.css   → 200, cache-control: public, max-age=31536000, immutable
GET /build/assets/none.css           → 404 {"error":"нет такого адреса", …}
```

Промах по файлу раздача отдаёт отказом парой со словом, и рисует его
каталог отказов приложения: клиент получает то же тело, что на промах
по адресу, а браузер — страницу 404 на рамке сайта. Своего ответа
на промах раздаче для этого не нужно. Остальное из `public` — favicon,
картинки, шрифты — раздаёт хвост у корня, `route.serve('/', 'public')`:
он уступает любому объявленному маршруту, а способ у него один — чтение,
поэтому запись туда, где своего маршрута нет, получает 405 с перечнем,
а не 404.

Сборщик (Vite, esbuild) ставит в имя файла отпечаток содержимого
и пишет соответствие в манифест `public/build/manifest.json`:

```json
{
  "resources/css/app.scss": { "file": "assets/app-BX7Yy2Qk.css" },
  "resources/js/app.js":    { "file": "assets/app-9f1c2ad3.js" }
}
```

Страница пишет исходное имя, а браузеру уходит имя с отпечатком:

```html
<link rel="stylesheet" href="@asset('resources/css/app.scss')">
--> <link rel="stylesheet" href="/build/assets/app-BX7Yy2Qk.css">
```

Тот же помощник лежит в контейнере под именем `asset` — адрес
собранного файла нужен не только странице, но и письму, и ответу в JSON:

```lua
app:get('asset')('resources/js/app.js')   --> /build/assets/app-9f1c2ad3.js
app:get('asset')('img/logo.svg')          --> /img/logo.svg, и предупреждение в журнал
```

**Отказа тут не бывает.** Нет манифеста, нет записи в нём, испорченный
JSON — путь уходит как есть (с ведущей чертой, чтобы он читался
от корня сайта, а не от адреса страницы), а в журнал ложится
предупреждение, и ровно одно на причину: страница рисуется десять раз
в секунду, и запись на каждый вызов залила бы журнал. Уронить страницу
из-за непрошедшей сборки нельзя: без стилей она некрасива, без страницы
— недоступна.

Манифест читается один раз и живёт в памяти: на боевом узле он меняется
вместе с выкладкой, то есть с перезапуском процесса. Перечитывание
конфигурации (`config:reload()`) тоже читает его заново: помощник
заводится на каждое применение, вместе с движком страниц. В разработке его
перечитывают по времени правки — сборка идёт на каждую правку стилей;
это раздел `app.assets` в `config/app.lua` выше (`APP_ASSETS_WATCH=true`).

Раздел `app.assets` главнее объявления, как `app.maintenance` у режима
обслуживания; `public = false` выключает помощника вовсе — тогда имени
`asset` в контейнере нет, а `@asset` в странице остаётся текстом, как
всякая незнакомая директива `tnt-template`. Объявление таблицей несёт
и путь: `public = { path = 'public', watch = true }`. Таблица без
`path` — то же, что `false`: соглашение её не дополняет, как не дополняет
оно и `downtime = { except = … }`.

Директива заводится до провайдеров, вместе с движком страниц: страницы
провайдера вправе на неё рассчитывать.

## Собранное заранее: `bootstrap/cache/`

Настройки и страницы собираются заранее, до подъёма узла, —
`tnt.framework.bootstrap`:

```sh
tt run -e "require('tnt.framework.bootstrap').config()"   # config/ + окружение → bootstrap/cache/config.lua
tt run -e "require('tnt.framework.bootstrap').views()"    # resources/views → bootstrap/cache/views/
tt run -e "require('tnt.framework.bootstrap').clear()"    # убрать и то и другое
```

Пока `bootstrap/cache/config.lua` на месте, приложение берёт разделы
из него и окружение не читает: правка переменной без пересборки файла
ничего не меняет. Исключение одно — секрет подписи ссылок `APP_KEY`:
он не раздел, и ядро читает его из окружения на каждом применении.
Тайны ложатся в файл открытым текстом: файл не для репозитория, и права
у него — только владельцу (`0600`).

Пишет и читает файл [`tnt-config`](https://github.com/tnt-skein/tnt-config/blob/main/docs/config.md)
(«Собранное заранее»): сборка подменяет файл целиком, и оборванная
оставляет прежний, а не половину нового; числа ложатся так, что читаются
обратно теми же. Роль читает файл как данные, а не как код: пустой файл,
код вместо данных, не словарь — отказ при загрузке роли
`приложение: собранные настройки не прочитаны: …`, а не приложение без
единой настройки. А в отказе приведения переменной, который сборка
печатает в терминал, значение тайны спрятано, даже если тайной имя объявил
только журнал (`log.secret_hints`). Сборка идёт из `tt run`, мимо применения,
где подсказки журнала в список окружения дописывает ядро, и зовёт ту же
связку ядра сама — `require('tnt.kernel.settings').link_secret_hints()` —
после загрузки файлов `config/` и до чтения окружения. Из кода приложения
`tt run` грузит только эти файлы, поэтому тайну журналу, которую должна
видеть и сборка, объявляют в них. Опечатка — взята не та переменная:

```lua
-- config/database.lua
table.insert(require('tnt.log').secret_hints, 'dsn')

return function(env)
    return { pool = env('DATABASE_DSN', 8) }
end
```

```sh
DATABASE_DSN=pg://user:hunter2@db tt run -e "require('tnt.framework.bootstrap').config()"
# database: переменная окружения DATABASE_DSN — целое число, а не [скрыто]
```

Без строки с `secret_hints` отказ показал бы DSN с паролем: у окружения
своей подсказки `dsn` нет (документ `tnt-env`, «Тайны»).

Страницы переводит движок самого приложения, а не отдельный, собранный
на стороне: иначе своих директив в кэше не оказалось бы. `views()`
грузит модуль `bootstrap/app.lua` по имени от корня, как его грузит
ядро на старте, и собирает приложение вне узла: разделы настроек — как
на старте, из `config/` и окружения либо из собранного файла, — затем
провайдеры и `build`. Страницы переводит движок `view` из этого
контейнера, и директивы, которые заводят провайдеры
(`app:get('view'):directive(…)`), ложатся в кэш вызовом, а не текстом:
у `demo` `views()` отдаёт `about, article, customer, errors.404,
layouts.app`, и `@date` провайдера `pages` в них уже вызов. Каталог
страниц и место переведённого — те, что у движка на старте: `views`
и `views_compiled` объявления либо соглашение. Тот же движок отдаёт
и сама роль — `role.offline_view()`.

Вне узла нет ни сервера, ни сети, ни применения конфигурации. В контейнере
`config`, `settings`, `env`, `log`, `clock` и — если они есть
у приложения — `downtime` и `view`, но нет `http` и служб по разделам
настроек — `cache`, `throttle`, `redis`, `db`, `mail`, `session`: кэшу
на спейсе нужен поднятый box, почта настраивает процесс, а провайдеру для
объявлений они ни к чему. Места узла в кластере вне узла тоже нет:
`instance`, `replicaset` и `group` пусты, `is_router` и `is_storage` —
`false`, `role` и `labels` — пустые таблицы. Поэтому `register`
провайдера только объявляет — `app:single(…)`, `app:value(…)`,
директивы, — а к узлу, серверу и службам идёт из сборщиков, лениво.
Сорвавшаяся сборка отказывает с именем приложения —
`приложение demo не собрано вне узла: …`, тайны в тексте спрятаны,
а созданное до отказа закрыто. Модуль `bootstrap/app.lua`, вернувший
не роль фреймворка, — отказ `модуль приложения bootstrap.app — не роль
tnt.framework`. Без модуля приложения либо без страниц у него переводится
`resources/views` движком без своих директив.

Переведённые страницы берутся, пока не старше исходника и пока набор
своих директив у движка на старте тот же, что у движка сборки: файл
помнит его последней строкой (документ `tnt-template`, «Перевод
заранее»). Правка шаблона и директива, заведённая без пересборки кэша,
переводятся заново сами — страница верна, только без выгоды кэша.
Маршруты и провайдеры собирать заранее нечего: они объявляются один раз
на применение конфигурации, а не на запрос, а список провайдеров и так
лежит в `bootstrap/providers.lua`.

## Что объявлено

`framework.new(spec)` принимает таблицу; незнакомое поле и поле не того
вида — ошибка при загрузке модуля роли. Незнакомое поле фреймворк отвергает
сам и перечисляет свои поля: `приложение: ключа «boot» нет, есть base,
build, cache, …`. Полей ядра `entry`, `view`, `error_page`
и `error_translate` в объявлении нет — их ядру собирает фреймворк,
и заданные приложением они молча пропали бы. `layers`, `groups`
и `view_data` есть: фреймворк отдаёт их ядру вместе со своими — слоем
сессий и токеном формы.

| Поле | Что это |
|---|---|
| `name` | имя журнала приложения и метка слоёв HTTP (`<name>.http`); правило имени — как у `tnt.log` |
| `base` | корень раскладки для соглашений; по умолчанию `.` — каталог приложения, из которого `tt` запускает узел |
| `prefix` | имя модуля корня раскладки — у приложения, которое едет роком; по умолчанию имя модуля — путь от корня |
| `dependencies` | роли ядра, которые применяются раньше; объявляются ядру только те, что у инстанса включены |
| `schema` | схема `tnt.validate` для раздела `roles_cfg` роли; без неё проверяется только «таблица или ничего» |
| `config` | каталог настроек приложения: файлы `<имя>.lua` с функцией от окружения → `config.<имя>` |
| `providers` | список имён модулей провайдеров по порядку (`bootstrap/providers.lua`) либо каталог; модуль — таблица с `register(app, config)` и `ready(app, status, key)` |
| `migrations` | каталог миграций: шаги `NNN_имя.lua` — `function(box)` либо `{ step, slice }` на `tnt-schema`; схема поднимается по `box.status` на ведущем с данными |
| `seeders` | каталог наполнителей: файл `<имя>.lua` — функция от контейнера либо `{ run, after, dev }`; запускает `role.seed` |
| `models` | модели приложения списком (`tnt-model`); по соглашению — файлы `app/models/*.lua` по алфавиту |
| `build(app, config)` | объявления контейнера сверх провайдеров: сборщики берут зависимости из `app`; последнее слово |
| `middleware` | слои приложения для HTTP — записи `tnt.middleware`, списком либо функцией `(app) -> список`, когда слою нужны настройки; идут под стражем отказов |
| `layers` | свои слои реестра — фабрики по именам, `{ имя = function(options) … end }`, таблицей либо функцией `(app) -> таблица`; ложатся рядом со слоем сессий, имя `session` занято (см. «Свои слои и группы») |
| `groups` | группы реестра — списки записей по именам, таблицей либо функцией `(app) -> таблица`; группа `web` приложения встаёт после слоя сессий и сама его не называет |
| `downtime` | режим обслуживания (`tnt-downtime`): путь к файлу-переключателю, таблица `{ path, except }` либо `false` — выключен; раздел `app.maintenance` настроек главнее |
| `public` | каталог для браузера (`public/`) либо `false`: отсюда берётся манифест сборки для `asset` и директивы `@asset`; таблицей — `{ path, build, watch }`, раздел `app.assets` настроек главнее |
| `views` | каталог страниц (`tnt-template`) либо `false`; движок лежит в контейнере под именем `view` и у роутера (`route.view(…)`), свой на применение — `config:reload()` подхватывает правку страниц; у движка — директивы `@canonical` и `@dump` |
| `lang` | каталог переводов (`tnt-i18n`), файл на язык, либо `false`; переводчик лежит в контейнере под именем `i18n`, у страниц — директивы `@lang`, `@choice`, `@locale`, на входе роутера — слой языка запроса; язык по умолчанию — `app.locale` |
| `cache` | кэш (`tnt-cache`): настройки либо `false`; лежит в контейнере под именем `cache`, раздел `cache` настроек главнее; без всего — в памяти. Драйверу `redis` достаётся клиент раздела `redis`; свой клиент — здесь, `{ driver = 'redis', redis = client }`: он не настройка, и разделу его не передать |
| `throttle` | ограничитель частоты (`tnt-throttle`): настройки либо `false`; лежит в контейнере под именем `throttle`, раздел `throttle` настроек главнее; без всего — в памяти. Клиент — как у `cache` |
| `files` | диски (`tnt-files`): настройки либо `false`; лежат в контейнере под именем `files`, раздел `files` главнее по диску; без раздела и объявления дисков нет. Функция `sign` и свой клиент ведра — здесь: в раздел их не положить |
| `cors` | межсайтовые запросы: настройки слоя `cors` (`tnt-middleware`) — `origins`, `methods`, `headers`, `expose`, `max_age`, `credentials` — и начало пути `path`, либо `false`; слой стоит первым на входе роутера, выше режима обслуживания; раздел `app.cors` настроек главнее по полю, `false` в нём выключает слой |
| `session` | сессии (`tnt-session`): `{ driver, name, lifetime, cookie, cache, cipher }` либо `false`; менеджер лежит в контейнере под именем `session`, его слой — в группе `web`; раздел `session` главнее, куки — по полю; без раздела и объявления сессий нет. Хранилище `cache` (либо функция от контейнера) и шифровальщик `cipher` — здесь: в раздел их не положить; без хранилища — кэш приложения |
| `config_cache`, `views_compiled` | собранные заранее настройки и переведённые страницы; по соглашению — `bootstrap/cache/` |
| `routes(router, app)` | маршруты HTTP — модуль или список модулей (`{ require('routes.web'), require('routes.api') }`); требует `roles.httpd` в `dependencies` |
| `iproto(app)` | таблица «имя → функция», публикуется глобалами для `lua_call`; модуль или список модулей, одно имя дважды — ошибка сборки |
| `ready(app, status, key)` | `on_event` ядра: `status` — `box.status` (`is_ro`, `status`, …), `key` — `config.apply` либо `box.status` |
| `view_data(app)` | общие данные страниц сверх токена формы: функция от контейнера отдаёт функцию от запроса, а та — таблицу; данные приложения главнее токена, данные обработчика главнее обоих (см. «Сессии») |
| `health_check(app, cfg)` | проверка готовности для встроенного реестра ядра; не должна уступать управление |

Возвращается таблица роли: `dependencies`, `validate`, `apply`,
`on_event`, `stop`, `health_check` (если объявлена), два средства
для проверок — `container()` (контейнер действующего применения или
`nil`) и `status()` (имена и рода объявлений без значений), — `layout()`
(что взято по соглашению) и `offline_view()` — движок страниц приложения,
собранного вне узла, для перевода заранее (см. «Собранное заранее»), —
`seed(opts)` — наполнение ([«Наполнители»](#наполнители-каталог-databaseseeders))
и `migrations(opts)` — состояние схемы узла ([«Что применено»](#что-применено-rolemigrations)).
На применении роль публикует функцию команд узла `<name>_command`
([«Команды узла»](#команды-узла-dbseed-и-migratestatus)).

## Что уходит ядру

Всё, что не каталог и не список: `name`, `dependencies`, `schema`,
`middleware`, `health_check` — как есть; `build` и `ready` — после
провайдеров (`build` первым кладёт в контейнер `downtime`, `i18n`,
`view` и службы по разделам настроек); слой `cors` по полю `cors`
и разделу `app.cors`, за ним слои режима обслуживания и языка — полем
`entry`, в этом порядке; страницы каталога
`resources/views/errors` — полем `error_page`; перевод слова отказа
по строкам `errors.*` — полем `error_translate`; слой сессий, группа
`web` и свои слои и группы приложения — полями `layers` и `groups`,
функциями от контейнера; токен формы при сессиях и поверх него
`view_data` приложения — полем `view_data`; функция команд узла —
первой в `iproto`; `routes` и `iproto` — после маршрутов и функций
провайдеров; `config`, `migrations` и `models` — прочитанными; `seeders`
ядру не уходит вовсе — его читает `role.seed`. Поведение роли,
стандартные имена контейнера, разделы `http`, `models`, `trace` — трасса
и её выгрузка в коллектор — и `notifier` — проведение находок через
встроенные проверки готовности, — журнал из раздела `log`, подъём схемы,
привязка моделей, перечитывание, останов и проверки — в документе
[`tnt-kernel`](https://github.com/tnt-skein/tnt-kernel/blob/main/docs/kernel.md);
внешние зависимости для проверок — у ядра (`require('tnt.kernel')._set_source`).

Пакет разложен по ответственностям: `tnt.framework` — сборка роли,
`framework.spec` — поля объявления и их виды, `framework.layout` —
соглашение о раскладке, `framework.config` — каталог настроек,
`framework.providers` — провайдеры, `framework.models` — каталог моделей,
`framework.migrations` — шаги схемы и новый файл миграции,
`framework.seeders` — наполнители: договор, порядок и запуск,
`framework.database` — `role.seed` и `role.migrations` с ответом
человеку и в JSON и команды `db:seed` и `migrate:status` на них,
`framework.commands` — команды узла и их функция iproto,
`framework.downtime` — режим обслуживания, `framework.services` — службы
по разделам настроек: клиент Redis, драйвер базы, кэш, ограничитель
частоты, почта и диски, `framework.session` — сессии по разделу
`session`, их слой и группа `web` вместе со своими слоями и группами
приложения, токен формы в данных страниц, `framework.cors` — слой межсайтовых запросов на входе
роутера по полю `cors` и разделу `app.cors`, `framework.bootstrap` —
собранное заранее, `framework.offline` —
приложение, собранное вне узла, для него же, `framework.asset` — пути
к собранным файлам по манифесту, `framework.lang` — переводы по каталогу
`lang/` и директивы страниц, `framework.canonical` — директива
`@canonical`, `framework.dump` — директива `@dump`, `framework.pages` —
страницы отказов по каталогу `resources/views/errors`, `framework.files` —
файлы каталогов и имена модулей.

Помощник `framework.migrations(dir)` отдаёт шаги каталога по номерам
версий — функцию либо таблицу `{ step, slice }`, как её вернул файл, —
ничего не регистрируя; им пользуются проверки, поднимающие схему
приложения на своём узле.

## Проверки

Проверки лежат в `test/` и идут на luatest; зовутся они через `make`,
который держит каталог узлов luatest своим.

```sh
make deps         # luatest, luacheck, luacov с cluacov, argparse и зависимости пакета в .rocks
make check        # форматирование, линт, проверки, покрытие с порогом 100 %
make test-large   # срез шага миграции на 300 000 строк: в make test пропускается
make mutants-all  # мутационное тестирование всех модулей
```

Ядро Tarantool и роль сервера подменяются внешними зависимостями ядра
(`require('tnt.kernel')._set_source`), смена учётки у команд узла —
`require('tnt.framework.commands')._set_source`; помощник проверок
`test/helper.lua` ставит их на один мир двойников и грузит исходники
пакета заново на каждую проверку. Роль зовётся так, как её зовёт ядро, —
`validate`, `apply`, `on_event`, `stop`, — а запросы идут тем же
обработчиком, который ядро ставит на сервер.

- `framework_test.lua` — раскладка по соглашению и приставка `prefix`,
  каталог настроек и журнал из `config/log.lua`, провайдеры списком
  и каталогом, миграции по файлам, модели каталога, собранное заранее
  и приложение вне узла, поля объявления и их отказы.
- `services_test.lua` — службы по разделам: клиент Redis на двойнике
  сервера, кэш и ограничитель на общем клиенте, драйвер базы с подменённым
  роком, диски, почта.
- `session_test.lua` — менеджер в контейнере, слой в реестре и группе
  `web`: кука первого ответа возвращается вторым запросом.
- `cors_test.lua` — поле `cors`, раздел `app.cors` и место слоя на входе:
  предварительный `OPTIONS` проходит весь путь до ответа.
- `lang_test.lua` — переводы, язык по умолчанию, директивы страниц, слой
  языка запроса и слово отказа.
- `canonical_test.lua`, `dump_test.lua`, `pages_test.lua`,
  `asset_test.lua` — директивы `@canonical` и `@dump`, страницы отказов,
  помощник путей к собранным файлам.
- `seeders_test.lua`, `database_test.lua`, `commands_test.lua` —
  наполнители, `role.seed` и `role.migrations`, генератор файла миграции,
  функция команд узла и команды на ней.
- `migrations_slice_test.lua` — срез шага из каталога на настоящем узле:
  срыв «fiber slice is exceeded» без среза и проход со срезом из файла;
  `migrations_large_test.lua` — то же на 300 000 строк под секундой ядра,
  целью `make test-large`.
- `space_cache_live_test.lua` — кэш и сессии на спейсах на узле
  по декларативной конфигурации: первое применение на пустой базе
  проходит, и спейсы следом заводят шаги миграции.

Проверок — 150, одна из них долгая (`make test-large`); покрытие строк —
100 % (1168 из 1168), убитых мутантов — 100 % (638 мутантов в двадцати
двух модулях).

## Чем пришлось поступиться

- **Команда узла идёт в файбере вызова.** Функция `<имя>_command`
  выполняет команду сразу, в файбере iproto: наполнитель без уступки
  держит узел, пока не кончит. Сценарий оператора ждёт ответа не дольше
  минуты и кончается кодом 69, а команда на узле доходит до конца —
  iproto не отменяет начатый вызов. Повтор безопасен: наполнители кладут
  записи заменой.
- **Право на функцию команд — право на все команды.** Команды идут
  от имени `admin`, и учётка, которой выдан `lua_call` на функцию, может
  и наполнять, и спрашивать состояние: поделить эти права между
  учётками нельзя. Наполнители разработки держит среда: в `production`
  `db:seed --dev` кончается отказом, код 1.
- **`@dump` виден каждому посетителю страницы.** Директива пишет
  в ответ, а не в журнал: показ видит тот, кто смотрит страницу, —
  разработчик, но и любой посетитель тоже. Забытая в странице, она
  и в бою показывает данные каждому, кто страницу открыл. Тайны под
  своими именами скрыты, а личные данные — имя, адрес, телефон — нет:
  правило тайн знает имена полей с ключами и паролями, а не с людьми.
  За режимом разработки `http.debug` директива не прячется: она пишет то,
  что автор страницы сам в неё поставил, как и `{{ }}`, а страница,
  которая в бою рисуется не так, как у разработчика, прятала бы забытый
  показ до первого включения режима. `@dump` в страницах, уходящих в бой,
  не оставляют.
- **Показ `@dump` не настраивается.** Всё, что стоит в скобках, —
  значения: второй аргумент настройками `describe` сделал бы
  `@dump(order, total)` неоднозначным, а пределы по умолчанию для
  страницы годятся. Глубже и длиннее показывает `describe` в консоли
  узла (документ `tnt-debug`).
- **Роки драйверов базы ставит приложение.** Пакеты драйверов — зависимости
  фреймворка, а роки `pg` и `mysql` под ними — форки с починками, которых
  на серверах роков нет: их собирает приложение, которому нужна база SQL,
  рецептом `tnt-postgres` и `tnt-mysql`. Узлу без раздела `database`
  с полем `driver` они не нужны вовсе.
- **Группа `web` начинается со слоя сессий.** Место слоя сессий в ней
  не настраивается: так порядок «сессия, потом сверка токена» один
  у всех маршрутов страниц. Слою, которому место раньше сессии, —
  ограничителю частоты, — заводят свою группу вокруг `web`
  и маршрутам страниц называют её.
