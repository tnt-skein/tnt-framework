--- Проверки межсайтовых запросов приложения: поле `cors`, раздел
--- `app.cors` и место слоя на входе роутера.
---
--- Запросы идут через ядро — тем же обработчиком, который ядро ставит
--- на сервер: предварительный `OPTIONS` к существующему пути проходит
--- весь путь до ответа, как у браузера, и видно, кто на него ответил —
--- слой или сам роутер.

local json = require('json')
local t = require('luatest')

local helper = dofile('test/helper.lua')
local testing = helper.testing

local g = t.group('tnt.framework.cors')

---@type TntKernelWorld
local world

---@type any
local framework

--- Каталог настроек с разделом `app.cors` из окружения.
local CORS = helper.path('config_cors')

--- Переменные окружения, которыми проверки правят раздел.
local VARIABLES = { 'TEST_CORS', 'TEST_CORS_ORIGINS', 'TEST_CORS_PATH' }

--- Свой источник и чужой.
local OWN = 'https://app.example.org'
local FOREIGN = 'https://evil.example.com'

--- Поля слоя, которые проверки не правят, — те же, что в примере
--- docs/framework.md.
local ALLOWED = {
    origins = { OWN },
    methods = { 'PUT', 'PATCH', 'DELETE' },
    headers = { 'content-type', 'authorization' },
    max_age = 600,
}

--- Поля объявления и раздела, которые называет отказ о незнакомом.
local FIELDS = 'credentials, expose, headers, max_age, methods, origins, path'

--- Сколько раз звали обработчик маршрута.
local handled = 0

g.before_each(function()
    world = helper.world()
    framework = helper.load(world)
    handled = 0
end)

g.after_each(function()
    -- Раздел, поправленный проверкой, следующей не достаётся.
    for _, name in ipairs(VARIABLES) do
        os.setenv(name, nil)
    end

    helper.forget_globals()
    helper.unload()
end)

--- Маршруты: данные API под `/api` и проверка живости мимо него.
---@param api table Роутер приложения
local function routes(api)
    local router = testing.module('tnt.router')

    api.get('/api/items', function()
        handled = handled + 1

        return router.text('список')
    end)

    api.put('/api/items/:id', function()
        handled = handled + 1

        return router.text('записано')
    end)

    api.post('/api/items', function()
        return nil, { status = 422, message = 'запись не подошла' }
    end)

    api.get('/health', function()
        return router.text('жив')
    end)
end

--- Объявление приложения с маршрутами и сервером HTTP.
---@param fields table|nil Поля объявления сверх маршрутов
---@return table
local function declared(fields)
    local spec = helper.spec(fields)

    spec.dependencies = { 'roles.httpd' }
    spec.routes = routes

    return spec
end

--- Роль приложения с маршрутами, применённая.
---@param fields table|nil Поля объявления сверх маршрутов
---@return any role
local function applied(fields)
    local role = framework.new(declared(fields))

    role.apply(nil)

    return role
end

--- Настройки слоя: общие поля и поверх них свои.
---@param fields table|nil
---@return table
local function allowed(fields)
    local options = table.copy(ALLOWED)

    for key, value in pairs(fields or {}) do
        options[key] = value
    end

    return options
end

--- Ответ собранного приложения.
---@param method string
---@param path string
---@param headers table|nil
---@return table
local function asked(method, path, headers)
    return world.server.options.handler(
        world.server,
        helper.incoming({ method = method, path = path, headers = headers })
    )
end

--- Предварительный запрос браузера за способом PUT.
---@param path string
---@param origin string|nil
---@return table
local function preflight(path, origin)
    return asked('OPTIONS', path, { origin = origin, ['access-control-request-method'] = 'PUT' })
end

-- ─── Предварительный запрос и ответы ────────────────────────────────────────

g.test_a_preflight_to_an_existing_route_is_answered_by_the_layer = function()
    applied({ cors = allowed() })

    -- На существующий путь роутер ответил бы сам — 204 с `Allow` и без
    -- разрешений; слой на входе отвечает раньше, и разрешение у ответа есть.
    local answer = preflight('/api/items/7', OWN)

    t.assert_equals(answer.status, 204)
    t.assert_equals(answer.headers['access-control-allow-origin'], OWN)
    t.assert_equals(answer.headers['access-control-allow-methods'], 'PUT, PATCH, DELETE')
    t.assert_equals(answer.headers['access-control-allow-headers'], 'content-type, authorization')
    t.assert_equals(answer.headers['access-control-max-age'], '600')
    t.assert_equals(answer.headers.vary, 'Origin')
    t.assert_equals(answer.headers.allow, nil, 'ответ слоя, а не роутера')
    t.assert_equals(handled, 0)

    -- Чужому источнику — отказ 403, нарисованный каталогом отказов.
    local refused = preflight('/api/items/7', FOREIGN)

    t.assert_equals(refused.status, 403)
    t.assert_equals(json.decode(refused.body).error, 'источник запроса не разрешён')
    t.assert_equals(refused.headers['access-control-allow-origin'], nil)
    t.assert_equals(refused.headers.vary, 'Origin')
    t.assert_equals(handled, 0)

    -- `OPTIONS` без спрошенного способа — не предварительный запрос,
    -- и на него по-прежнему отвечает роутер.
    local plain = asked('OPTIONS', '/api/items/7', { origin = OWN })

    t.assert_equals(plain.status, 204)
    t.assert_equals(plain.headers.allow, 'OPTIONS, PUT')
end

g.test_responses_and_refusals_carry_the_permission = function()
    applied({ cors = allowed() })

    local own = asked('GET', '/api/items', { origin = OWN })

    t.assert_equals(own.body, 'список')
    t.assert_equals(own.headers['access-control-allow-origin'], OWN)
    t.assert_equals(own.headers.vary, 'Origin')

    -- Чужой простой запрос проходит, но без разрешения.
    local foreign = asked('GET', '/api/items', { origin = FOREIGN })

    t.assert_equals(foreign.body, 'список')
    t.assert_equals(foreign.headers['access-control-allow-origin'], nil)
    t.assert_equals(foreign.headers.vary, 'Origin')

    -- Промах по адресу тоже несёт разрешение: слой стоит до поиска
    -- маршрута, и сценарий прочтёт 404, а не сетевую ошибку.
    local missing = asked('GET', '/nowhere', { origin = OWN })

    t.assert_equals(missing.status, 404)
    t.assert_equals(missing.headers['access-control-allow-origin'], OWN)

    -- И отказ обработчика.
    local unfit = asked('POST', '/api/items', { origin = OWN })

    t.assert_equals(unfit.status, 422)
    t.assert_equals(json.decode(unfit.body).error, 'запись не подошла')
    t.assert_equals(unfit.headers['access-control-allow-origin'], OWN)
end

g.test_the_layer_stands_above_downtime = function()
    local fio = require('fio')
    local directory = fio.tempdir()
    local role = applied({ cors = allowed(), downtime = fio.pathjoin(directory, 'down') })

    role.container():get('downtime'):down({ message = 'выкатываем 2.0', retry = 120 })

    -- Отказ закрытого приложения сценарий чужой страницы читает целиком:
    -- слово и срок повтора, а не сетевую ошибку.
    local closed = asked('GET', '/api/items', { origin = OWN })

    t.assert_equals(closed.status, 503)
    t.assert_equals(closed.headers['retry-after'], '120')
    t.assert_equals(closed.headers['access-control-allow-origin'], OWN)
    t.assert_equals(json.decode(closed.body).error, 'выкатываем 2.0')

    -- Предварительный запрос отвечен слоем и в закрытом приложении:
    -- следом браузер пошлёт сам запрос и получит на него 503.
    t.assert_equals(preflight('/api/items/7', OWN).status, 204)
    t.assert_equals(handled, 0)

    fio.rmtree(directory)
end

g.test_the_path_narrows_the_layer = function()
    applied({ cors = allowed({ path = '/api' }) })

    t.assert_equals(asked('GET', '/api/items', { origin = OWN }).headers['access-control-allow-origin'], OWN)

    -- Мимо фильтра — как будто слоя нет: ни разрешения, ни `Vary`.
    local health = asked('GET', '/health', { origin = OWN })

    t.assert_equals(health.body, 'жив')
    t.assert_equals(health.headers['access-control-allow-origin'], nil)
    t.assert_equals(health.headers.vary, nil)
end

-- ─── Объявление и раздел app.cors ───────────────────────────────────────────

g.test_without_the_declaration_and_the_section_there_is_no_layer = function()
    t.assert_equals(framework.CORS, 'cors')

    applied()

    -- На предварительный запрос отвечает роутер — без разрешений.
    local answer = preflight('/api/items/7', OWN)

    t.assert_equals(answer.status, 204)
    t.assert_equals(answer.headers.allow, 'OPTIONS, PUT')
    t.assert_equals(answer.headers['access-control-allow-origin'], nil)
    t.assert_equals(asked('GET', '/api/items', { origin = OWN }).headers.vary, nil)
end

g.test_the_section_app_cors_beats_the_declaration_by_field = function()
    os.setenv('TEST_CORS_ORIGINS', 'https://admin.example.org, https://*.example.net')

    local role = applied({ config = CORS, cors = allowed() })

    -- Источники — из раздела, способы и срок — из объявления.
    local answer = preflight('/api/items/7', 'https://admin.example.org')

    t.assert_equals(answer.headers['access-control-allow-origin'], 'https://admin.example.org')
    t.assert_equals(answer.headers['access-control-allow-methods'], 'PUT, PATCH, DELETE')
    t.assert_equals(answer.headers['access-control-max-age'], '600')
    t.assert_equals(preflight('/api/items/7', 'https://shop.example.net').status, 204)
    t.assert_equals(
        preflight('/api/items/7', OWN).status,
        403,
        'источник объявления перебит разделом'
    )

    -- Путь — тоже полем раздела.
    os.setenv('TEST_CORS_PATH', '/api')
    role.apply(nil)

    t.assert_equals(asked('GET', '/health', { origin = 'https://admin.example.org' }).headers.vary, nil)

    -- Раздел без источников их не стирает: перечитывание берёт объявление.
    os.setenv('TEST_CORS_ORIGINS', nil)
    role.apply(nil)

    t.assert_equals(preflight('/api/items/7', OWN).headers['access-control-allow-origin'], OWN)

    -- `false` в разделе выключает слой, объявленный в коде.
    os.setenv('TEST_CORS', 'false')
    role.apply(nil)

    t.assert_equals(preflight('/api/items/7', OWN).headers.allow, 'OPTIONS, PUT')
end

g.test_the_section_alone_brings_the_layer = function()
    os.setenv('TEST_CORS_ORIGINS', OWN)

    applied({ config = CORS })

    local own = asked('GET', '/api/items', { origin = OWN })

    t.assert_equals(own.headers['access-control-allow-origin'], OWN)

    -- Без способов в настройках браузеру названы только простые.
    t.assert_equals(preflight('/api/items/7', OWN).headers['access-control-allow-methods'], nil)
end

g.test_false_in_the_declaration_beats_the_section = function()
    os.setenv('TEST_CORS_ORIGINS', OWN)

    applied({ config = CORS, cors = false })

    t.assert_equals(preflight('/api/items/7', OWN).headers.allow, 'OPTIONS, PUT')
end

-- ─── Отказы ─────────────────────────────────────────────────────────────────

g.test_unfit_settings_are_refused = function()
    -- Вид поля и опечатка в имени — при загрузке роли.
    t.assert_error_msg_equals(
        'приложение: cors должно быть table или false, получено number',
        framework.new,
        helper.spec({ cors = 7 })
    )
    t.assert_error_msg_equals(
        'приложение: cors: ключа «orgins» нет, есть ' .. FIELDS,
        framework.new,
        helper.spec({ cors = { orgins = { OWN } } })
    )

    -- Настройки слоя — при применении, словом самого слоя и без места
    -- в исходнике: чинить надо настройку, а не строку фреймворка.
    local bare = framework.new(declared({ cors = {} }))

    t.assert_error_msg_equals(
        'приложение test.app не собрано: настройки слоя cors.origins — массив, а не nil',
        bare.apply,
        nil
    )

    local greedy = framework.new(declared({ cors = { origins = { '*' }, credentials = true } }))

    t.assert_error_msg_equals(
        'приложение test.app не собрано: настройки слоя cors: источник «*» вместе с credentials браузер отвергает, '
            .. 'а подставить вместо него пришедший источник — значит отдать ответы с куками посетителя '
            .. 'любому сайту; назовите источники списком',
        greedy.apply,
        nil
    )

    -- Раздел не того вида — тоже при применении: разделы читаются там.
    local odd = framework.new(declared({ config = helper.path('config_cors_odd') }))

    t.assert_error_msg_equals(
        'приложение test.app не собрано: приложение: app.cors должно быть table или false, получено string',
        odd.apply,
        nil
    )
end

g.test_the_entries_of_the_layer = function()
    local cors = testing.module('tnt.framework.cors')

    t.assert_equals(cors.entries(nil, nil), {})
    t.assert_equals(cors.entries(false, { cors = { origins = { OWN } } }), {})
    t.assert_equals(cors.entries({ origins = { OWN } }, { cors = false }), {})
    t.assert_equals(cors.entries(nil, { cors = box.NULL }), {})

    -- `null` из YAML — не раздел: слой собирается по объявлению.
    t.assert_equals(#cors.entries({ origins = { OWN } }, { cors = box.NULL }), 1)

    -- Запись входа: сам слой, его имя в цепочке и фильтр по пути.
    local entries = cors.entries({ origins = { OWN }, path = '/api' }, {})

    t.assert_equals(#entries, 1)
    t.assert_type(entries[1][1], 'function')
    t.assert_equals(entries[1].name, 'cors')
    t.assert_equals(entries[1].path, '/api')

    -- Раздел — только таблицей либо `false`, и только со своими полями.
    t.assert_error_msg_equals(
        'приложение: app.cors должно быть table или false, получено string',
        cors.entries,
        { origins = { OWN } },
        { cors = 'yes' }
    )
    t.assert_error_msg_equals(
        'приложение: раздел app.cors: ключа «orgins» нет, есть ' .. FIELDS,
        cors.entries,
        nil,
        { cors = { orgins = { OWN } } }
    )
end
