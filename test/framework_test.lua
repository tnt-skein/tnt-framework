--- Проверки раскладки приложения: каталог настроек, провайдеры списком
--- и каталогом, миграции по файлам, журнал из config/log.lua.
---
--- Ядро Tarantool здесь не поднимается: конфигурация и роль сервера
--- подменены двойниками через внешние зависимости ядра, а роль зовётся так, как её
--- зовёт ядро — `validate`, `apply`, `on_event`, `stop`.

local t = require('luatest')

local helper = dofile('test/helper.lua')
local testing = helper.testing

local g = t.group('tnt.framework')

--- Записи журнала: ядро пишет о сборке и о сорвавшихся событиях.
local trap = testing.capture_log()

---@type TntKernelWorld
local world

---@type any
local framework

--- Объявление приложения с нужными полями поверх минимального.
local spec = helper.spec

--- Каталог образцов настроек рядом с проверками.
local CONFIG_DIR = helper.path('config')

--- Корень образца со своей директивой страниц: сборка страниц заранее
--- пишет в его `bootstrap/cache`.
local PAGES = helper.path('app_with_pages')

-- Мир двойников и свежие исходники на каждую проверку; ловушка журнала
-- ставится после загрузки — журнал перезагружается вместе с исходниками.
g.before_each(function()
    world = helper.world()
    framework = helper.load(world)
    trap.forget()
end)

g.after_each(function()
    helper.forget_globals()
    helper.unload()

    -- Собранное проверкой, сорвавшейся посреди, не достаётся следующей.
    require('fio').rmtree(PAGES .. '/bootstrap/cache')
end)

g.after_all(trap.release)

-- ─── Объявление — ядру ──────────────────────────────────────────────────────

g.test_one_route_module_and_the_rest_of_the_declaration_reach_the_kernel = function()
    local router = testing.module('tnt.router')
    local role = framework.new(spec({
        dependencies = { 'roles.httpd' },
        routes = function(api)
            api.get('/ping', function()
                return router.text('pong')
            end)
        end,
        iproto = function()
            return {
                ping = function()
                    return 'pong'
                end,
            }
        end,
    }))

    role.apply(nil)

    t.assert_equals(world.server.options.handler(world.server, helper.incoming({ path = '/ping' })).body, 'pong')
    t.assert_equals(rawget(_G, 'ping')(), 'pong')

    -- Незнакомое поле фреймворк отвергает сам и называет свои поля:
    -- ядро назвало бы свои — без каталогов фреймворка, зато с `entry`
    -- и `view`, которые фреймворк собирает ему сам. Свои виды полей —
    -- каталоги и функции — фреймворк тоже проверяет сам, до ядра.
    local fields = 'base, build, cache, config, config_cache, cors, dependencies, downtime, files, groups, '
        .. 'health_check, iproto, lang, layers, middleware, migrations, models, name, prefix, providers, public, '
        .. 'ready, routes, schema, seeders, session, throttle, view_data, views, views_compiled'

    t.assert_error_msg_equals(
        'приложение: ключа «boot» нет, есть ' .. fields,
        framework.new,
        spec({ boot = 1 })
    )
    t.assert_error_msg_equals(
        'приложение: ключа «entry» нет, есть ' .. fields,
        framework.new,
        spec({ entry = function() end })
    )
    t.assert_error_msg_equals(
        'приложение: ключа «view» нет, есть ' .. fields,
        framework.new,
        spec({ view = function() end })
    )
    t.assert_error_msg_equals('приложение объявляется таблицей', framework.new, 'app')
    t.assert_error_msg_equals(
        'приложение: config должно быть string, получено table',
        framework.new,
        spec({ config = {} })
    )

    -- Без маршрутов сервер не требуется: список пуст, и ядро его не видит.
    framework.new(spec()).apply(nil)
end

-- ─── Раскладка по соглашению ────────────────────────────────────────────────

g.test_a_layout_inside_a_package_names_its_modules_itself = function()
    -- Приложение, которое едет роком: каталог находится по самому модулю,
    -- а имя модуля из пути установленного рока не выводится — его
    -- называет `prefix`. Вложенность при этом сохраняется: `routes/web`
    -- под приставкой `pkg.app` — это `pkg.app.routes.web`.
    -- Пакета с таким именем на машине нет, и его модули подкладываются
    -- под именами, которые обязано получиться у раскладки: не получится —
    -- загрузчик скажет об этом сам.
    local inside = {
        'bootstrap.providers',
        'config.greeting',
        'routes.web',
        'routes.middleware',
        'routes.iproto',
    }

    for _, name in ipairs(inside) do
        package.loaded['pkg.app.' .. name] = require(helper.module_name('app_by_convention.') .. name)
    end

    -- Настройки под приставкой — свои: по пути каталога нашёлся бы
    -- другой модуль с другим словом, и это было бы видно по приветствию.
    package.loaded['pkg.app.config.greeting'] = function()
        return { word = 'из пакета' }
    end

    local role = framework.new(spec({
        dependencies = { 'roles.httpd' },
        base = helper.path('app_by_convention'),
        prefix = 'pkg.app',
    }))

    local layout = role.layout()

    for _, name in ipairs(inside) do
        package.loaded['pkg.app.' .. name] = nil
    end

    role.apply(nil)

    t.assert_equals(role.container():get('greeting'), 'из пакета, router-001-a')
    rawset(_G, 'greeting', nil)

    t.assert_equals(layout.providers, 'pkg.app.bootstrap.providers')
    t.assert_equals(layout.routes, { 'pkg.app.routes.web' })
    t.assert_equals(layout.middleware, 'pkg.app.routes.middleware')
    t.assert_equals(layout.iproto, 'pkg.app.routes.iproto')

    -- Каталоги остаются путями: их читают с диска, а не подключают.
    t.assert_equals(layout.views, helper.path('app_by_convention/resources/views'))
end

g.test_the_layout_is_found_by_convention_from_the_base = function()
    os.setenv('TEST_GREETING', 'здравствуйте')

    local role = framework.new(spec({
        dependencies = { 'roles.httpd' },
        base = helper.path('app_by_convention'),
    }))

    t.assert_equals(role.layout(), {
        config = helper.path('app_by_convention/config'),
        migrations = helper.path('app_by_convention/database/migrations'),
        seeders = helper.path('app_by_convention/database/seeders'),
        models = { helper.module_name('app_by_convention.app.models.user') },
        providers = helper.module_name('app_by_convention.bootstrap.providers'),
        routes = { helper.module_name('app_by_convention.routes.web') },
        middleware = helper.module_name('app_by_convention.routes.middleware'),
        iproto = helper.module_name('app_by_convention.routes.iproto'),
        downtime = helper.path('app_by_convention/storage/framework/down'),
        views = helper.path('app_by_convention/resources/views'),
        public = helper.path('app_by_convention/public'),
    })

    role.apply(nil)

    local answer = world.server.options.handler(world.server, helper.incoming({ path = '/' }))
    local page = world.server.options.handler(world.server, helper.incoming({ path = '/page' }))

    -- В странице стоит `@asset('resources/css/app.scss')`, а браузеру
    -- уходит имя с отпечатком из `public/build/manifest.json`.
    t.assert_equals(
        page.body,
        '<title>app</title><link rel="stylesheet" href="/build/assets/app-BX7Yy2Qk.css">'
            .. '<p>привет, &lt;мир&gt;</p>\n'
    )
    t.assert_str_contains(page.headers['content-type'], 'text/html')

    t.assert_equals(answer.body, 'здравствуйте, router-001-a')
    t.assert_equals(answer.headers['x-served-by'], 'router-001-a')
    t.assert_equals(rawget(_G, 'greeting')(), 'здравствуйте, router-001-a')

    -- Второй шаг схемы — из объявления модели, а модель привязана ядром
    -- по месту узла: мир двойников — роутер vshard.
    t.assert_equals(testing.module('tnt.schema').target_version(), 2)
    t.assert_equals(require(helper.module_name('app_by_convention.app.models.user')).bound(), 'sharded')
    t.assert_equals(role.status().models, { source = 'sharded', sharded = false, serves = false, spaces = { 'users' } })

    -- Наполнители — тоже по соглашению, с контейнером применения.
    t.assert_equals(role.seed(), { seeded = { { name = 'greetings', count = 1 } }, skipped = {} })
    t.assert_equals(rawget(_G, 'seeded_greeting'), 'здравствуйте')

    os.setenv('TEST_GREETING', nil)
    rawset(_G, 'greeting', nil)
    rawset(_G, 'seeded_greeting', nil)
end

g.test_the_pages_of_refusal_are_found_by_convention_and_reach_the_catalog = function()
    os.setenv('TEST_GREETING', 'здравствуйте')

    local role = framework.new(spec({
        dependencies = { 'roles.httpd' },
        base = helper.path('app_by_convention'),
    }))

    role.apply(nil)

    -- Браузер просит страницу, и отказ приходит ею: шаблоном приложения
    -- из `resources/views/errors`, который ядру отдаёт фреймворк.
    local page = world.server.options.handler(
        world.server,
        helper.incoming({ path = '/нет-такого-адреса', headers = { accept = 'text/html' } })
    )

    t.assert_equals(page.status, 404)
    t.assert_equals(page.headers['content-type'], 'text/html; charset=utf-8')
    t.assert_equals(page.body, '<p>404: нет такого адреса</p>\n')

    -- Сценарию тот же отказ уходит прежним телом по договору.
    local body =
        world.server.options.handler(world.server, helper.incoming({ path = '/нет-такого-адреса' }))

    t.assert_equals(body.headers['content-type'], 'application/json; charset=utf-8')

    os.setenv('TEST_GREETING', nil)
    rawset(_G, 'greeting', nil)
end

g.test_an_explicit_field_beats_the_convention_and_an_empty_base_gives_nothing = function()
    local role = framework.new(spec({
        dependencies = { 'roles.httpd' },
        base = helper.path('app_by_convention'),
        config = CONFIG_DIR,
        providers = {},
        routes = function() end,
        iproto = function()
            return {
                ping = function()
                    return 'своё'
                end,
            }
        end,
    }))

    t.assert_equals(role.layout(), {
        migrations = helper.path('app_by_convention/database/migrations'),
        seeders = helper.path('app_by_convention/database/seeders'),
        models = { helper.module_name('app_by_convention.app.models.user') },
        middleware = helper.module_name('app_by_convention.routes.middleware'),
        downtime = helper.path('app_by_convention/storage/framework/down'),
        views = helper.path('app_by_convention/resources/views'),
        public = helper.path('app_by_convention/public'),
    })

    os.setenv('TEST_MAIL_PASSWORD', 'x')
    role.apply(nil)

    t.assert_equals(rawget(_G, 'ping')(), 'своё')
    t.assert_equals(rawget(_G, 'greeting'), nil)

    os.setenv('TEST_MAIL_PASSWORD', nil)

    -- Корень без раскладки: соглашение ничего не находит и молчит.
    t.assert_equals(framework.new(spec({ base = helper.path('config') })).layout(), {})
    t.assert_error_msg_equals(
        'приложение: base должно быть string, получено number',
        framework.new,
        spec({ base = 7 })
    )
end

-- ─── Режим обслуживания ─────────────────────────────────────────────────────

--- Запрос к серверу двойника.
---@param path string
---@param headers table|nil
---@return table
local function asked(path, headers)
    return world.server.options.handler(world.server, helper.incoming({ path = path, headers = headers }))
end

g.test_downtime_closes_the_application_before_its_own_layers = function()
    local fio = require('fio')
    local directory = fio.tempdir()
    local own_calls = 0

    local role = framework.new(spec({
        dependencies = { 'roles.httpd' },
        downtime = { path = fio.pathjoin(directory, 'down'), except = { '/health' } },
        middleware = {
            function(request, nxt)
                own_calls = own_calls + 1

                return nxt(request)
            end,
        },
        routes = function(api)
            api.get('/', function()
                return { status = 200, body = 'дело' }
            end)
            api.get('/health', function()
                return { status = 200, body = 'жив' }
            end)
        end,
    }))

    role.apply(nil)

    local mode = role.container():get('downtime')

    t.assert_equals(asked('/').status, 200)
    t.assert_equals(own_calls, 1)

    mode:down({ message = 'выкатываем 2.0', retry = 120, secret = 'k7z' })

    -- Закрытому приложению не отвечает ни один его слой: 503 рисует
    -- каталог отказов, свой слой до запроса не допущен.
    local refused = asked('/')

    t.assert_equals(refused.status, 503)
    t.assert_equals(refused.headers['retry-after'], '120')
    t.assert_str_contains(refused.body, 'выкатываем 2.0')
    t.assert_equals(own_calls, 1)

    t.assert_equals(asked('/health').body, 'жив', 'исключение проходит')
    t.assert_equals(
        asked('/nowhere').status,
        503,
        'и путь, которого нет: по 404 читались бы маршруты'
    )
    t.assert_equals(asked('/k7z').status, 302)
    t.assert_equals(asked('/', { cookie = 'tnt_downtime=k7z' }).body, 'дело', 'обход по тайне')

    -- Переключатель переживает перечитывание: он в файле, а не в контейнере.
    role.apply(nil)

    t.assert_equals(asked('/').status, 503)

    role.container():get('downtime'):up()

    t.assert_equals(asked('/').status, 200)

    fio.rmtree(directory)
end

g.test_downtime_is_off_by_false_and_refused_by_kind = function()
    local role = framework.new(spec({
        dependencies = { 'roles.httpd' },
        base = helper.path('app_by_convention'),
        downtime = false,
    }))

    t.assert_equals(role.layout().downtime, nil)

    os.setenv('TEST_GREETING', 'здравствуйте')
    role.apply(nil)

    t.assert_equals(role.container():has('downtime'), false)
    t.assert_equals(asked('/').status, 200)

    os.setenv('TEST_GREETING', nil)
    rawset(_G, 'greeting', nil)

    t.assert_error_msg_equals(
        'приложение: downtime должно быть string, table или false, получено number',
        framework.new,
        spec({ downtime = 7 })
    )
    t.assert_error_msg_equals(
        'приложение: views должно быть string или false, получено number',
        framework.new,
        spec({ views = 7 })
    )

    -- Страницы выключаются так же: false, и имени view в контейнере нет.
    local pageless = framework.new(spec({
        dependencies = { 'roles.httpd' },
        base = helper.path('app_by_convention'),
        views = false,
    }))

    t.assert_equals(pageless.layout().views, nil)
    os.setenv('TEST_GREETING', 'здравствуйте')
    pageless.apply(nil)
    t.assert_equals(pageless.container():has('view'), false)
    os.setenv('TEST_GREETING', nil)
    rawset(_G, 'greeting', nil)

    -- Без файла и без раздела app режима нет вовсе.
    local bare = framework.new(spec({}))

    bare.apply(nil)

    t.assert_equals(bare.container():has('downtime'), false)
end

-- ─── Собранные файлы: каталог public и помощник asset ───────────────────────

g.test_the_public_directory_brings_the_asset_helper_and_the_page_directive = function()
    local role = framework.new(spec({
        dependencies = { 'roles.httpd' },
        base = helper.path('app_by_convention'),
    }))

    os.setenv('TEST_GREETING', 'здравствуйте')
    role.apply(nil)

    -- Помощник лежит в контейнере под именем `asset`: он нужен не только
    -- страницам — адрес собранного файла уходит и в JSON, и в письмо.
    t.assert_equals(role.container():get('asset')('resources/js/app.js'), '/build/assets/app-9f1c2ad3.js')

    os.setenv('TEST_GREETING', nil)
    rawset(_G, 'greeting', nil)
end

g.test_without_the_public_directory_there_is_no_asset_at_all = function()
    -- `public = false` выключает помощника так же, как `views = false` —
    -- страницы: имени в контейнере нет, и директивы у движка тоже.
    local role = framework.new(spec({
        dependencies = { 'roles.httpd' },
        base = helper.path('app_by_convention'),
        public = false,
    }))

    t.assert_equals(role.layout().public, nil)

    os.setenv('TEST_GREETING', 'здравствуйте')
    role.apply(nil)

    t.assert_equals(role.container():has('asset'), false)

    -- Директивы у движка тоже нет, и страница печатает её как есть —
    -- так `tnt-template` поступает со всякой незнакомой директивой
    -- (`@media` в стилях страницы им и остаётся).
    local page = role.container():get('view'):render('greeting', { greeting = 'привет', who = 'мир' })

    t.assert_str_contains(page, "@asset('resources/css/app.scss')")

    os.setenv('TEST_GREETING', nil)
    rawset(_G, 'greeting', nil)

    t.assert_error_msg_equals(
        'приложение: public должно быть string, table или false, получено number',
        framework.new,
        spec({ public = 7 })
    )
end

g.test_config_app_maintenance_beats_the_declaration_and_knows_one_driver = function()
    local fio = require('fio')
    local directory = fio.tempdir()

    os.setenv('TEST_MAINTENANCE_PATH', fio.pathjoin(directory, 'из-настроек'))

    local role = framework.new(spec({
        dependencies = { 'roles.httpd' },
        config = helper.path('config_app'),
        downtime = fio.pathjoin(directory, 'из-объявления'),
        routes = function(api)
            api.get('/health', function()
                return { status = 200, body = 'жив' }
            end)
        end,
    }))

    role.apply(nil)

    local mode = role.container():get('downtime')

    t.assert_equals(mode.path, fio.pathjoin(directory, 'из-настроек'))
    t.assert_equals(mode.except, { ['/health'] = true })

    -- Путь из объявления остаётся, когда раздел его не задаёт.
    os.setenv('TEST_MAINTENANCE_PATH', nil)
    role.apply(nil)

    t.assert_equals(role.container():get('downtime').path, fio.pathjoin(directory, 'из-объявления'))

    os.setenv('TEST_MAINTENANCE_DRIVER', 'redis')

    t.assert_error_msg_equals(
        'приложение test.app не собрано: '
            .. 'приложение: режим обслуживания: драйвер redis не поддерживается, есть только file',
        role.apply,
        nil
    )

    os.setenv('TEST_MAINTENANCE_DRIVER', nil)
    fio.rmtree(directory)
end

-- ─── Кэш и собранное заранее ────────────────────────────────────────────────

g.test_cache_lives_in_the_container_and_takes_the_cache_section = function()
    local role = framework.new(spec({}))

    role.apply(nil)

    local store = role.container():get('cache')

    store:put('a', 1)

    t.assert_equals(store:get('a'), 1)
    t.assert_equals(store:status(), { name = 'memory', driver = 'memory', prefix = '', ttl = nil })

    -- Объявление задаёт умолчания, раздел настроек главнее.
    os.setenv('TEST_CACHE_PREFIX', 'из-настроек:')

    local configured = framework.new(spec({
        config = helper.path('config_cache'),
        cache = { prefix = 'из-объявления:', ttl = 30 },
    }))

    configured.apply(nil)

    t.assert_equals(
        configured.container():get('cache'):status(),
        { name = 'memory', driver = 'memory', prefix = 'из-настроек:', ttl = 30 }
    )

    -- Клиент Redis — не настройка: он приходит объявлением, а раздел
    -- настроек дополняет его приставкой.
    local sent = {}
    local client = {
        command = function(_, args)
            table.insert(sent, args[1])

            return 'OK'
        end,
    }
    local shared = framework.new(spec({
        config = helper.path('config_cache'),
        cache = { driver = 'redis', redis = client },
    }))

    shared.apply(nil)
    shared.container():get('cache'):put('a', 1)

    t.assert_equals(
        shared.container():get('cache'):status(),
        { name = 'redis', driver = 'redis', prefix = 'из-настроек:', ttl = nil }
    )
    t.assert_equals(sent, { 'SET' })

    os.setenv('TEST_CACHE_PREFIX', nil)

    local without = framework.new(spec({ cache = false }))

    without.apply(nil)

    t.assert_equals(without.container():has('cache'), false)
    t.assert_error_msg_equals(
        'приложение: cache должно быть table или false, получено number',
        framework.new,
        spec({ cache = 7 })
    )
end

--- Временный корень приложения с файлом настроек `config/app.lua`.
---
--- Модули настроек подключаются по имени, и временный каталог для этого
--- добавляется в package.path как есть: `?.lua` без приставки.
---@param body string Тело функции от окружения
---@param preamble string|nil Что файл делает при загрузке, до функции
---@return string base
local function app_root_with_config(body, preamble)
    local fio = require('fio')
    local base = fio.tempdir()

    fio.mktree(fio.pathjoin(base, 'config'))

    local file = fio.open(fio.pathjoin(base, 'config', 'app.lua'), { 'O_WRONLY', 'O_CREAT' }, 420)

    file:write((preamble or '') .. 'return function(env) return ' .. body .. ' end')
    file:close()

    if not package.path:find('^%?%.lua;') then
        package.path = '?.lua;' .. package.path
    end

    return base
end

g.test_bootstrap_config_freezes_the_environment_until_cleared = function()
    local fio = require('fio')
    local bootstrap = testing.module('tnt.framework.bootstrap')
    local base = app_root_with_config("{ name = env('TEST_APP_NAME', 'demo'), list = { 1, 'два' }, on = true }")

    os.setenv('TEST_APP_NAME', 'собранное')

    local path = bootstrap.config(base)

    t.assert_equals(path, base .. '/bootstrap/cache/config.lua')
    t.assert_equals(dofile(path), { app = { name = 'собранное', list = { 1, 'два' }, on = true } })
    -- Тайны в файле лежат открытым текстом: читать его вправе только владелец.
    t.assert_equals(fio.stat(path).mode % 512, tonumber('600', 8), 'права 0600')

    -- Файл на месте — окружение больше не читается, раскладка это показывает.
    os.setenv('TEST_APP_NAME', 'живое')

    local role = framework.new(spec({ base = base }))

    t.assert_equals(role.layout().config_cache, base .. '/bootstrap/cache/config.lua')
    role.apply(nil)
    t.assert_equals(role.container():get('config').app.name, 'собранное')

    -- Копия на применение: правка в контейнере не портит собранное.
    role.container():get('config').app.name = 'испорчено'
    role.apply(nil)
    t.assert_equals(role.container():get('config').app.name, 'собранное')

    t.assert_equals(bootstrap.clear(base), { base .. '/bootstrap/cache/config.lua' })
    t.assert_equals(bootstrap.clear(base), {})
    t.assert_equals(fio.path.exists(base .. '/bootstrap/cache'), false, 'пустой каталог убран')

    local live = framework.new(spec({ base = base }))

    live.apply(nil)
    t.assert_equals(live.container():get('config').app.name, 'живое')

    os.setenv('TEST_APP_NAME', nil)

    -- Испорченный собранный файл — отказ при загрузке роли.
    fio.mktree(fio.dirname(path))

    local broken = fio.open(path, { 'O_WRONLY', 'O_CREAT', 'O_TRUNC' }, 420)

    broken:write('return 7')
    broken:close()

    local unread =
        'приложение: собранные настройки не прочитаны: файл настроек %s не разобран: %s'

    t.assert_error_msg_equals(
        unread:format(path, 'в нём не словарь настроек, а число'),
        framework.new,
        spec({ base = base })
    )

    -- Собранный файл — данные, а не код: исполнить из него ничего нельзя.
    broken = fio.open(path, { 'O_WRONLY', 'O_CREAT', 'O_TRUNC' }, 420)
    broken:write("return { app = { passwd = io.open('/etc/passwd'):read('*a') } }")
    broken:close()

    t.assert_error_msg_equals(
        unread:format(path, path .. ":1: attempt to index global 'io' (a nil value)"),
        framework.new,
        spec({ base = base })
    )
    -- Собранный файл с чужим расширением — ошибка объявления, без места.
    t.assert_error_msg_equals(
        ('приложение: файл настроек %s/bootstrap/cache/config: расширение — .yaml, .yml, .json либо .lua'):format(
            base
        ),
        framework.new,
        spec({ base = base, config_cache = base .. '/bootstrap/cache/config' })
    )
    t.assert_error_msg_equals('каталога настроек nowhere/config нет', bootstrap.config, 'nowhere')

    -- Корень по умолчанию и «.» — рабочий каталог, без приставки в пути.
    t.assert_error_msg_equals('каталога настроек config нет', bootstrap.config)
    t.assert_error_msg_equals('каталога страниц resources/views нет', bootstrap.views, '.')

    fio.rmtree(base)
end

g.test_bootstrap_views_translate_pages_ahead_and_the_role_uses_them = function()
    local fio = require('fio')
    local bootstrap = testing.module('tnt.framework.bootstrap')
    local base = fio.tempdir()

    fio.mktree(fio.pathjoin(base, 'resources', 'views', 'layouts'))
    fio.copyfile(
        helper.path('app_by_convention/resources/views/greeting.thtml.lua'),
        fio.pathjoin(base, 'resources', 'views', 'greeting.thtml.lua')
    )
    fio.copyfile(
        helper.path('app_by_convention/resources/views/layouts/app.thtml.lua'),
        fio.pathjoin(base, 'resources', 'views', 'layouts', 'app.thtml.lua')
    )

    t.assert_equals(bootstrap.views(base), { 'greeting', 'layouts.app' })
    t.assert_equals(fio.path.is_file(base .. '/bootstrap/cache/views/layouts/app.lua'), true)

    local role = framework.new(spec({
        dependencies = { 'roles.httpd' },
        base = base,
        routes = require(helper.module_name('app_by_convention.routes.web')),
    }))

    t.assert_equals(role.layout().views_compiled, base .. '/bootstrap/cache/views')
    role.apply(nil)

    t.assert_equals(role.container():get('view').compiled, base .. '/bootstrap/cache/views')
    t.assert_equals(asked('/page').status, 200)

    t.assert_equals(bootstrap.clear(base), { base .. '/bootstrap/cache/views' })
    t.assert_error_msg_equals(
        'каталога страниц nowhere/resources/views нет',
        bootstrap.views,
        'nowhere'
    )

    fio.rmtree(base)
end

g.test_bootstrap_views_translate_with_the_directives_of_the_application = function()
    local fio = require('fio')
    local bootstrap = testing.module('tnt.framework.bootstrap')
    local template = testing.module('tnt.template')
    local compiled = PAGES .. '/bootstrap/cache/views'
    local path = compiled .. '/about.lua'

    -- Как `make view-cache` приложения: модуль bootstrap/app.lua
    -- собирается вне узла, и директиву @since заводит его провайдер.
    t.assert_equals(bootstrap.views(PAGES), { 'about', 'customer' })

    local code = testing.read_file(path)

    t.assert_str_contains(code, '_r.handlers["since"](started_at)')
    -- В отпечатке — и директивы фреймворка: движок страниц на старте
    -- заводит их сам, и кэш без них был бы движку чужим.
    local stamp = '[directive @dump, directive @since, markup @canonical]'

    t.assert_equals(code:sub(-#stamp), stamp)

    -- Старт с переведёнными: страница рисует дату, и рисует её из файла —
    -- подмена текста в нём это показывает.
    local swapped = fio.open(path, { 'O_WRONLY', 'O_TRUNC' })

    swapped:write((code:gsub('Поднят', 'Собран')))
    swapped:close()

    local role = framework.new(spec({ dependencies = { 'roles.httpd' }, base = PAGES }))

    t.assert_equals(role.layout().views_compiled, compiled)
    role.apply(nil)
    t.assert_equals(asked('/about').body, '<p>Собран 01.01.1970.</p>\n')
    role.stop()

    -- Кэш, собранный движком без директив приложения, — так его собирала
    -- прежняя сборка: `@since` лежит в файле текстом, а файл свежий.
    -- Отпечаток не тот, и на старте страница переводится заново.
    template.warm(template.new({ path = PAGES .. '/resources/views', compiled = compiled }))
    t.assert_str_contains(testing.read_file(path), '"<p>Поднят @since(started_at).</p>')

    local restarted = framework.new(spec({ dependencies = { 'roles.httpd' }, base = PAGES }))

    restarted.apply(nil)
    t.assert_equals(asked('/about').body, '<p>Поднят 01.01.1970.</p>\n')

    t.assert_equals(bootstrap.clear(PAGES), { compiled })
end

g.test_offline_view_assembles_the_application_up_to_its_build_without_the_node = function()
    local names, seen, title
    local closed = false

    local role = framework.new(spec({
        dependencies = { 'roles.httpd' },
        base = PAGES,
        -- На узле такой кэш не собрался бы вовсе, а вне узла кэш
        -- не заводится: провайдеру для объявлений он ни к чему.
        cache = { driver = 'nowhere' },
        build = function(app, config)
            names = app:names()
            seen = config
            title = app:get('settings'):string('pages.title')

            app:single('probe', function()
                return {}
            end, {
                close = function()
                    closed = true
                end,
            })
            app:get('probe')
            app:get('view'):condition('admin', function()
                return true
            end)
        end,
    }))

    local view = role.offline_view()

    t.assert_equals(view.path, PAGES .. '/resources/views')
    t.assert_equals(
        view.compiled,
        PAGES .. '/bootstrap/cache/views',
        'каталога ещё нет, а место — по соглашению'
    )
    t.assert_equals(
        view.kinds,
        { since = 'directive', admin = 'condition', canonical = 'markup', dump = 'directive' },
        'директивы фреймворка, провайдера и build'
    )

    -- Стандартные имена — как у ядра, кроме сервера: его вне узла нет.
    t.assert_equals(names, { 'clock', 'config', 'env', 'log', 'settings', 'view' })

    -- Разделы — как на старте; места узла в кластере вне узла нет.
    t.assert_equals(seen, {
        role = {},
        labels = {},
        is_router = false,
        is_storage = false,
        pages = { title = 'О приложении' },
    })
    t.assert_equals(title, 'О приложении', 'набор settings — из того же снимка')
    t.assert_equals(closed, true, 'созданное вне узла закрыто')
    t.assert_equals(role.container(), nil, 'узел не тронут')

    -- Явный каталог переведённых — туда же, куда смотрит движок на старте.
    local explicit = framework.new(spec({
        dependencies = { 'roles.httpd' },
        base = PAGES,
        views_compiled = 'var/pages',
    }))

    t.assert_equals(explicit.offline_view().compiled, 'var/pages')

    -- Без страниц движка нет; без каталога настроек — только место узла.
    local pageless = framework.new(spec({
        build = function(_, config)
            seen = config
        end,
    }))

    t.assert_equals(pageless.offline_view(), nil)
    t.assert_equals(seen, { role = {}, labels = {}, is_router = false, is_storage = false })
end

g.test_offline_view_refuses_with_the_name_and_closes_what_it_built = function()
    local closed = false
    local role = framework.new(spec({
        build = function(app)
            app:single('probe', function()
                return {}
            end, {
                close = function()
                    closed = true
                end,
            })
            app:get('probe')
            error('нет связи с pg://user:hunter2@db', 0)
        end,
    }))

    t.assert_error_msg_equals(
        'приложение test.app не собрано вне узла: нет связи с pg://user:[скрыто]@db',
        role.offline_view
    )
    t.assert_equals(closed, true)

    -- Модуль bootstrap/app.lua, вернувший не роль фреймворка, — отказ
    -- сборки страниц, а не падение на вызове пустоты.
    local odd = helper.path('app_not_a_role')
    local refusal = 'модуль приложения '
        .. helper.module_name('app_not_a_role.bootstrap.app')
        .. ' — не роль tnt.framework'
    local bootstrap = testing.module('tnt.framework.bootstrap')

    t.assert_error_msg_equals(refusal, bootstrap.views, odd)

    -- Модуль без возврата: `require` отдаёт `true`.
    rawset(package.loaded, helper.module_name('app_not_a_role.bootstrap.app'), true)

    t.assert_error_msg_equals(refusal, bootstrap.views, odd)
end

g.test_bootstrap_config_refuses_what_cannot_be_written_as_data = function()
    local fio = require('fio')
    local bootstrap = testing.module('tnt.framework.bootstrap')

    local with_function = app_root_with_config('{ handler = print }')

    t.assert_error_msg_equals(
        'настройки.app.handler — функция, а в файл настроек ложатся только данные',
        bootstrap.config,
        with_function
    )

    local with_odd_key = app_root_with_config('{ [true] = 1 }')

    t.assert_error_msg_equals(
        'настройки.app: ключ — строка либо число, а не логическое значение',
        bootstrap.config,
        with_odd_key
    )

    -- Ключи не-имена и числа пишутся в скобках, числа раньше строк.
    local mixed = app_root_with_config("{ ['a-b'] = 1, [2] = 'два', z = {}, [1] = 'один' }")
    local path = bootstrap.config(mixed)

    t.assert_equals(dofile(path), { app = { ['a-b'] = 1, 'один', 'два', z = {} } })
    t.assert_str_contains(
        testing.read_file(path),
        '{\n        [1] = "один",\n        [2] = "два",\n        ["a-b"] = 1,\n        z = {},\n    }'
    )

    -- Каталог кэша, куда не записать: на его месте файл.
    fio.rmtree(fio.pathjoin(mixed, 'bootstrap'))

    local blocked = fio.open(fio.pathjoin(mixed, 'bootstrap'), { 'O_WRONLY', 'O_CREAT' }, 420)

    blocked:close()

    t.assert_str_contains(
        select(2, pcall(bootstrap.config, mixed)),
        ('каталог %s/bootstrap/cache не создан: '):format(mixed)
    )

    for _, base in ipairs({ with_function, with_odd_key, mixed }) do
        fio.rmtree(base)
    end
end

g.test_bootstrap_config_writes_a_wide_table_in_key_order = function()
    -- Два с половиной десятка ключей вразброс и числа в хеш-части:
    -- на трёх-четырёх ключах порядок записи совпадает и у сортировки
    -- с ошибкой в сравнении, а на широком словаре — уже нет. Числа
    -- сравниваются как числа: строкой 1000 встала бы раньше 4.
    local fio = require('fio')
    local bootstrap = testing.module('tnt.framework.bootstrap')
    local alphabetical = (
        'alpha bravo charlie delta echo foxtrot golf hotel india juliett kilo lima mike '
        .. 'november oscar papa quebec romeo sierra tango uniform victor whiskey xray yankee zulu'
    ):split(' ')
    local shuffled = (
        'mike zulu alpha quebec echo xray golf november bravo whiskey lima charlie tango '
        .. 'hotel yankee delta papa india uniform foxtrot romeo juliett sierra kilo victor oscar'
    ):split(' ')
    local fields = { '[30] = 30', '[4] = 4', '[1000] = 1000', '[17] = 17', '[9] = 9' }

    for _, name in ipairs(shuffled) do
        table.insert(fields, ('%s = %q'):format(name, name))
    end

    local base = app_root_with_config('{ ' .. table.concat(fields, ', ') .. ' }')
    local expected = { '[4] = 4,', '[9] = 9,', '[17] = 17,', '[30] = 30,', '[1000] = 1000,' }

    for _, name in ipairs(alphabetical) do
        table.insert(expected, ('%s = %q,'):format(name, name))
    end

    local path = bootstrap.config(base)

    t.assert_str_contains(testing.read_file(path), '{\n        ' .. table.concat(expected, '\n        ') .. '\n    }')

    fio.rmtree(base)
end

g.test_bootstrap_config_hides_values_of_names_the_journal_declared_secret = function()
    -- Сборка идёт из `tt run`, мимо применения, где связку тайн журнала
    -- делает ядро, а отказ её печатается в терминал и журнал сборки.
    -- Из кода приложения `tt run` грузит только файлы `config/`, поэтому
    -- тайну журналу здесь объявляет сам файл настроек при загрузке.
    local fio = require('fio')
    local env = testing.module('tnt.env')
    local bootstrap = testing.module('tnt.framework.bootstrap')
    local body = "{ pool = env('TEST_DATABASE_DSN', 8) }"
    local plain = app_root_with_config(body)
    local declared = app_root_with_config(body, "table.insert(require('tnt.log').secret_hints, 'dsn') ")
    local hints = #env.secret_hints

    os.setenv('TEST_DATABASE_DSN', 'pg://user:hunter2@db')

    -- Отрицательный контроль: пока журнал `dsn` тайной не объявил, своей
    -- подсказки на это имя у окружения нет и значение в отказе видно —
    -- ниже его прячет именно связка, а не собственный список окружения.
    local _, shown = pcall(bootstrap.config, plain)

    -- Тот же корень дважды — повтор связки: дописанная подсказка покрывает
    -- себя сама, и список не раздувается.
    local _, first = pcall(bootstrap.config, declared)
    local _, second = pcall(bootstrap.config, declared)

    os.setenv('TEST_DATABASE_DSN', nil)

    t.assert_equals(
        shown,
        'app: переменная окружения TEST_DATABASE_DSN — целое число, а не «pg://user:hunter2@db»'
    )
    t.assert_equals(
        first,
        'app: переменная окружения TEST_DATABASE_DSN — целое число, а не [скрыто]'
    )
    t.assert_equals(second, first)
    t.assert_equals(#env.secret_hints, hints + 1)
    t.assert_equals(env.secret_hints[hints + 1], 'dsn')
    t.assert_equals(
        fio.path.exists(fio.pathjoin(declared, 'bootstrap')),
        false,
        'отказ файла не пишет'
    )

    for _, base in ipairs({ plain, declared }) do
        fio.rmtree(base)
    end
end

-- ─── Каталог настроек ───────────────────────────────────────────────────────

g.test_config_files_become_sections_of_the_config_built_from_the_environment = function()
    os.setenv('TEST_MAIL_PASSWORD', 'hunter2')
    os.setenv('TEST_APP_PORT', '9')

    local role = framework.new(spec({ config = CONFIG_DIR }))

    role.apply(nil)

    local config = role.container():get('config')

    -- Настоящая переменная главнее умолчания и приведена по его роду.
    t.assert_equals(config.app, { debug = false, port = 9 })
    t.assert_equals(config.mail, { password = 'hunter2' })
    t.assert_equals(config.role, {})

    -- Окружение перечитывается на каждом применении.
    os.setenv('TEST_APP_PORT', nil)
    role.apply(nil)

    t.assert_equals(role.container():get('config').app.port, 8080)

    os.setenv('TEST_MAIL_PASSWORD', nil)
end

g.test_a_missing_required_variable_and_a_wrong_kind_refuse_the_settings = function()
    local role = framework.new(spec({ config = CONFIG_DIR }))

    os.setenv('TEST_MAIL_PASSWORD', nil)

    t.assert_error_msg_equals(
        'настройки роли test.app: mail: переменная окружения TEST_MAIL_PASSWORD не задана',
        role.validate,
        nil
    )

    os.setenv('TEST_MAIL_PASSWORD', 'hunter2')
    os.setenv('TEST_APP_PORT', 'восемь')

    t.assert_error_msg_equals(
        'настройки роли test.app: app: переменная окружения TEST_APP_PORT — целое число, а не «восемь»',
        role.validate,
        nil
    )

    os.setenv('TEST_APP_PORT', nil)
    os.setenv('TEST_MAIL_PASSWORD', nil)
end

g.test_a_broken_config_directory_is_refused_at_declaration = function()
    t.assert_error_msg_equals(
        'приложение: каталог настроек '
            .. helper.path('no_such_dir')
            .. ' не прочитан',
        framework.new,
        spec({ config = helper.path('no_such_dir') })
    )
    t.assert_error_msg_equals(
        'приложение: модуль настроек '
            .. helper.module_name('config_broken.plain')
            .. ' должен вернуть функцию от окружения',
        framework.new,
        spec({ config = helper.path('config_broken') })
    )
    t.assert_error_msg_equals(
        'приложение: имя настроек role занято ядром',
        framework.new,
        spec({ config = helper.path('config_reserved') })
    )

    local role = framework.new(spec({ config = helper.path('config_odd') }))

    t.assert_error_msg_equals(
        'настройки роли test.app: text должен вернуть таблицу, получено string',
        role.validate,
        nil
    )
end

g.test_config_log_is_handed_to_the_kernel_journal_on_every_apply = function()
    local role = framework.new(spec({ config = helper.path('config_log') }))

    local journal = assert(world.journal, 'мир заводит двойник журнала')

    os.setenv('TEST_LOG_LEVEL', 'debug')
    role.apply(nil)

    -- Только заданное: вид остаётся из раздела log конфигурации кластера,
    -- карта модулей не трогается.
    t.assert_equals(journal.applied, { { level = 'debug' } })
    t.assert_equals(journal.cfg.format, 'json')
    t.assert_equals(journal.cfg.modules, { ['tnt.pool'] = 'warn' })

    -- Карта модулей — строкой из .env; дополняется, а не заменяется:
    -- уровень соседа остаётся.
    os.setenv('TEST_LOG_FORMAT', 'plain')
    os.setenv('TEST_LOG_MODULES', 'tnt.pool=debug, app.http=warn')
    role.apply(nil)

    t.assert_equals(journal.applied[2], {
        level = 'debug',
        format = 'plain',
        modules = { ['tnt.pool'] = 'debug', ['app.http'] = 'warn' },
    })
    t.assert_equals(role.container():get('config').log, {
        level = 'debug',
        format = 'plain',
        modules = 'tnt.pool=debug, app.http=warn',
    })

    journal.cfg.modules = { ['tnt.http'] = 'error' }
    os.setenv('TEST_LOG_MODULES', 'tnt.pool=debug')
    role.apply(nil)

    t.assert_equals(journal.applied[3].modules, { ['tnt.http'] = 'error', ['tnt.pool'] = 'debug' })

    -- Карта таблицей берётся как есть.
    os.setenv('TEST_LOG_POOL', 'verbose')
    role.apply(nil)

    t.assert_equals(journal.applied[4].modules, { ['tnt.http'] = 'error', ['tnt.pool'] = 'verbose' })
    os.setenv('TEST_LOG_POOL', nil)

    -- Имя модуля — из букв, цифр, точки, подчёркивания и дефиса; уровень
    -- обязателен; пустая запись — тоже отказ, а не пропуск.
    os.setenv('TEST_LOG_MODULES', 'my-app.http=warn')
    role.apply(nil)

    t.assert_equals(journal.applied[5].modules['my-app.http'], 'warn')

    for _, broken in ipairs({ 'tnt.pool', 'tnt.pool=', '=debug', 'a+b=debug', 'tnt.pool=debug,,x=y' }) do
        os.setenv('TEST_LOG_MODULES', broken)

        t.assert_error_msg_contains(
            'настройки роли test.app: log: modules: ожидалось имя=уровень, а не «',
            role.apply,
            nil
        )
    end

    os.setenv('TEST_LOG_MODULES', 'tnt.pool=debug,,x=y')

    t.assert_error_msg_equals(
        'настройки роли test.app: log: modules: ожидалось имя=уровень, а не «»',
        role.apply,
        nil
    )

    -- Запись без уровня и карта не того вида — отказ с именем файла.
    os.setenv('TEST_LOG_MODULES', 'tnt.pool')

    t.assert_error_msg_equals(
        'настройки роли test.app: log: modules: ожидалось имя=уровень, а не «tnt.pool»',
        role.apply,
        nil
    )

    os.setenv('TEST_LOG_MODULES', 'true')

    t.assert_error_msg_equals(
        'настройки роли test.app: log: modules: ожидалась таблица или строка имя=уровень, получено boolean',
        role.apply,
        nil
    )

    os.setenv('TEST_LOG_MODULES', nil)

    -- Отказ ядра называет файл, а прежнее применение остаётся.
    local container = role.container()

    journal.cfg = setmetatable({ modules = {} }, {
        __call = function()
            error('Incorrect value for option level', 0)
        end,
    })

    t.assert_error_msg_equals(
        'настройки роли test.app: log: Incorrect value for option level',
        role.apply,
        nil
    )
    t.assert_is(role.container(), container)

    os.setenv('TEST_LOG_LEVEL', nil)
    os.setenv('TEST_LOG_FORMAT', nil)
end

g.test_the_real_journal_accepts_the_settings_of_the_process = function()
    -- Настоящий журнал процесса проверок принимает те же поля,
    -- что и двойник.
    world.journal = nil
    framework = helper.load(world)

    local role = framework.new(spec({ config = helper.path('config_log') }))
    local journal = require('log')
    local level = journal.cfg.level

    os.setenv('TEST_LOG_LEVEL', 'debug')
    role.apply(nil)

    t.assert_equals(journal.cfg.level, 'debug')

    journal.cfg({ level = level })
    os.setenv('TEST_LOG_LEVEL', nil)
end

g.test_migrations_are_registered_by_version_from_the_file_name = function()
    local migrations = testing.module('tnt.schema')

    framework.new(spec({ migrations = helper.path('migrations') }))

    t.assert_equals(migrations.target_version(), 2)

    -- Второе объявление того же каталога шаги не регистрирует заново:
    -- реестр один на процесс, и шаг дважды он не принимает.
    framework.new(spec({ migrations = helper.path('migrations') }))

    t.assert_equals(migrations.target_version(), 2)

    -- Сам помощник — чистый: отдаёт шаги по номерам, ничего не регистрируя.
    local steps = framework.migrations(helper.path('migrations'))

    t.assert_equals({ type(steps[1]), type(steps[2]) }, { 'function', 'function' })

    -- Номер версии — число, а не ширина: `7_notes.lua` — шаг седьмой
    -- версии. Образцы рядом пишут номер тремя цифрами и этого не видят.
    local fio = require('fio')
    local short = fio.tempdir()
    local step = fio.open(fio.pathjoin(short, '7_notes.lua'), { 'O_WRONLY', 'O_CREAT' }, 420)

    step:write('return function() end')
    step:close()

    local versions = {}

    for version, found in pairs(framework.migrations(short)) do
        table.insert(versions, { version, type(found) })
    end

    t.assert_equals(versions, { { 7, 'function' } })
    fio.rmtree(short)

    t.assert_error_msg_equals(
        'приложение: миграция '
            .. helper.path('migrations_unnumbered/customers.lua')
            .. ' '
            .. 'должна начинаться с номера версии: 001_имя.lua',
        framework.new,
        spec({ migrations = helper.path('migrations_unnumbered') })
    )
    t.assert_error_msg_equals(
        'приложение: миграция '
            .. helper.path('migrations_plain/003_plain.lua')
            .. ': '
            .. 'ключа «version» нет, есть slice, step',
        framework.new,
        spec({ migrations = helper.path('migrations_plain') })
    )
end

-- Долгому шагу файл отдаёт таблицу со срезом: она уходит ядру как есть,
-- и ядро отдаёт срез реестру. Что срез шагу достался, видно только
-- на узле — это `migrations_slice_test.lua`.
g.test_a_migration_file_may_return_a_step_with_a_slice = function()
    local migrations = testing.module('tnt.schema')
    local registered = {}

    migrations.register = function(version, step, opts)
        registered[version] = { step = type(step), opts = opts }
    end

    local steps = framework.migrations(helper.path('migrations_sliced'))

    t.assert_equals({ type(steps[1].step), steps[1].slice }, { 'function', 30 })

    framework.new(spec({ migrations = helper.path('migrations_sliced') }))

    t.assert_equals(registered, { [1] = { step = 'function', opts = { slice = 30 } } })

    -- Негодный срез — отказ сборки с именем файла: номер версии здесь
    -- ничего не сказал бы, чинить надо файл.
    t.assert_error_msg_equals(
        'приложение: миграция '
            .. helper.path('migrations_bad_slice/001_statuses.lua')
            .. ': '
            .. 'slice — число больше 0, а не 0',
        framework.new,
        spec({ migrations = helper.path('migrations_bad_slice') })
    )
end

-- ─── Модели ─────────────────────────────────────────────────────────────────

g.test_models_are_taken_from_app_models_and_an_explicit_list_beats_the_directory = function()
    local model = testing.module('tnt.model')
    local Own = model.define({
        space = 'own',
        fields = { { 'id', 'unsigned', primary = true }, model.bucket_of('id') },
    })

    -- Явный список перебивает каталог: в раскладке моделей нет.
    local role = framework.new(spec({
        dependencies = { 'roles.httpd' },
        base = helper.path('app_by_convention'),
        models = { Own },
        providers = {},
    }))

    t.assert_equals(role.layout().models, nil)

    os.setenv('TEST_MAIL_PASSWORD', 'x')
    role.apply(nil)
    os.setenv('TEST_MAIL_PASSWORD', nil)

    t.assert_equals(Own.bound(), 'sharded')
    t.assert_equals(role.status().models.spaces, { 'own' })
    t.assert_equals(require(helper.module_name('app_by_convention.app.models.user')).bound(), nil)

    role.stop()

    t.assert_equals(Own.bound(), nil)

    -- Файл каталога, вернувший не модель, — ошибка при загрузке роли
    -- с именем модуля.
    t.assert_error_msg_equals(
        'приложение: модель '
            .. helper.module_name('models_odd.plain')
            .. ' должна быть объявлена через model.define(…)',
        testing.module('tnt.framework.models').of,
        helper.path('models_odd')
    )
    t.assert_error_msg_equals(
        'приложение: каталог моделей ' .. helper.path('no_such_dir') .. ' не прочитан',
        testing.module('tnt.framework.models').of,
        helper.path('no_such_dir')
    )
end

g.test_providers_register_in_file_order_before_build_and_ready_in_the_same_order = function()
    local role = framework.new(spec({
        providers = helper.path('providers'),
        build = function(app)
            table.insert(rawget(_G, 'provider_order'), 'build')
            app:replace('farewell', 'до свидания')
        end,
        ready = function()
            table.insert(rawget(_G, 'provider_order'), 'ready')
        end,
    }))

    role.apply(nil)

    t.assert_equals(rawget(_G, 'provider_order'), { '10_greeting.register', '20_farewell.register', 'build' })
    t.assert_equals(role.container():get('greeting'), 'привет, router-001-a')
    t.assert_equals(role.container():get('farewell'), 'до свидания')

    role.on_event(nil, 'config.apply', { is_ro = false })

    t.assert_equals(rawget(_G, 'provider_order'), {
        '10_greeting.register',
        '20_farewell.register',
        'build',
        '10_greeting.ready:config.apply:false',
        '30_watcher.ready',
        'ready',
    })
end

g.test_providers_may_be_listed_by_module_name_in_their_own_order = function()
    -- Список — как bootstrap/providers.php: порядок задаёт он сам,
    -- а не имя файла.
    rawset(_G, 'provider_order', {})

    local role = framework.new(spec({
        providers = {
            helper.module_name('providers.30_watcher'),
            helper.module_name('providers.10_greeting'),
        },
    }))

    role.apply(nil)
    role.on_event(nil, 'config.apply', { is_ro = false })

    -- Третий по имени файла отработал первым: порядок задал список.
    t.assert_equals(rawget(_G, 'provider_order'), {
        '10_greeting.register',
        '30_watcher.ready',
        '10_greeting.ready:config.apply:false',
    })

    -- В журнале провайдер из списка зовётся именем модуля целиком.
    trap.forget()
    role.on_event(nil, 'box.status', { is_ro = true, fail_first = true })

    t.assert_equals(
        trap.records()[1].record.fields.name,
        'провайдер ' .. helper.module_name('providers.10_greeting')
    )

    t.assert_error_msg_equals(
        'приложение: providers: запись №2 должна быть именем модуля',
        framework.new,
        spec({ providers = { helper.module_name('providers.10_greeting'), 7 } })
    )
    t.assert_error_msg_equals(
        'приложение: providers должно быть table, получено number',
        framework.new,
        spec({ providers = 7 })
    )
end

g.test_a_provider_may_bring_its_own_routes_and_iproto_functions = function()
    local router = testing.module('tnt.router')
    local role = framework.new(spec({
        dependencies = { 'roles.httpd' },
        providers = helper.path('providers_routes'),
        routes = function(api)
            api.get('/ping', function()
                return router.text('pong')
            end)
        end,
    }))

    role.apply(nil)

    -- Маршруты провайдера и приложения живут на одном роутере,
    -- функции iproto — в одном наборе.
    t.assert_equals(
        world.server.options.handler(world.server, helper.incoming({ path = '/pages/about' })).body,
        'о приложении'
    )
    t.assert_equals(world.server.options.handler(world.server, helper.incoming({ path = '/ping' })).body, 'pong')
    t.assert_equals(rawget(_G, 'pages_about')(), 'о приложении')

    rawset(_G, 'pages_about', nil)

    t.assert_error_msg_equals(
        'приложение: маршруты провайдера '
            .. helper.module_name('providers_routes.pages')
            .. ' '
            .. 'требуют roles.httpd в dependencies',
        framework.new,
        spec({ providers = helper.path('providers_routes') })
    )
end

g.test_a_failing_provider_is_journaled_and_does_not_stop_the_others = function()
    local role = framework.new(spec({ providers = helper.path('providers') }))

    role.apply(nil)
    trap.forget()
    role.on_event(nil, 'box.status', { is_ro = true, fail_first = true })

    t.assert_equals(rawget(_G, 'provider_order')[#rawget(_G, 'provider_order')], '30_watcher.ready')

    local last = trap.records()[1]

    t.assert_equals(last.level, 'error')
    t.assert_equals(
        last.record.message,
        'действие готовности «провайдер '
            .. helper.module_name('providers.10_greeting')
            .. '» сорвалось '
            .. 'на box.status: первый провайдер сорвался'
    )
    t.assert_equals(last.record.fields.name, 'провайдер ' .. helper.module_name('providers.10_greeting'))
end

g.test_broken_providers_are_refused_at_declaration = function()
    t.assert_error_msg_equals(
        'приложение: каталог провайдеров '
            .. helper.path('no_such_dir')
            .. ' не прочитан',
        framework.new,
        spec({ providers = helper.path('no_such_dir') })
    )
    t.assert_error_msg_equals(
        'приложение: провайдер '
            .. helper.module_name('providers_odd.plain')
            .. ' должен вернуть таблицу с register и ready',
        framework.new,
        spec({ providers = helper.path('providers_odd') })
    )
    t.assert_error_msg_equals(
        'приложение: провайдер '
            .. helper.module_name('providers_empty.nothing')
            .. ' ничего не делает',
        framework.new,
        spec({ providers = helper.path('providers_empty') })
    )
    t.assert_error_msg_equals(
        'приложение: провайдер '
            .. helper.module_name('providers_typo.boot')
            .. ': нет такого действия — boot',
        framework.new,
        spec({ providers = helper.path('providers_typo') })
    )

    package.loaded[helper.module_name('providers_typo.boot')] = { register = 'позже' }

    t.assert_error_msg_equals(
        'приложение: провайдер '
            .. helper.module_name('providers_typo.boot')
            .. ': register должно быть функцией',
        framework.new,
        spec({ providers = helper.path('providers_typo') })
    )

    package.loaded[helper.module_name('providers_typo.boot')] = nil
end
