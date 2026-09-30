--- Проверки сессий по разделу session: менеджер в контейнере, слой
--- в реестре слоёв приложения и в группе web — рядом со своими слоями
--- и группами приложения.
---
--- Запросы идут через ядро — тем же обработчиком, который ядро ставит
--- на сервер: кука, выданная первым ответом, возвращается вторым
--- запросом, как её вернул бы браузер.

local digest = require('digest')
local t = require('luatest')

local helper = dofile('test/helper.lua')
local testing = helper.testing

local g = t.group('tnt.framework.session')

---@type TntKernelWorld
local world

---@type any
local framework

--- Каталог настроек с разделом session.
local SESSION = helper.path('config_session')

--- Переменные окружения, которыми проверки правят раздел.
local VARIABLES = { 'TEST_SESSION_DRIVER', 'TEST_SESSION_NAME', 'TEST_SESSION_LIFETIME', 'TEST_SESSION_CIPHER' }

g.before_each(function()
    world = helper.world()
    framework = helper.load(world)
end)

g.after_each(function()
    helper.forget_globals()
    helper.unload()

    -- Раздел, поправленный проверкой, следующей не достаётся.
    for _, name in ipairs(VARIABLES) do
        os.setenv(name, nil)
    end
end)

--- Маршруты: страница под группой web считает визиты в сессии, данные
--- API идут мимо группы и говорят, была ли у них сессия.
---@param api table Роутер приложения
local function routes(api)
    local router = testing.module('tnt.router')

    api.get('/visit', function(request)
        if request.session == nil then
            return router.text('без сессии')
        end

        local visits = (request.session:get('visits') or 0) + 1

        request.session:put('visits', visits)

        return router.text(tostring(visits))
    end, { middleware = { framework.WEB } })

    api.get('/data', function(request)
        return router.text(tostring(request.session))
    end)
end

--- Роль приложения с маршрутами, применённая.
---@param config string|nil Каталог настроек
---@param overrides table|nil Поля объявления сверх каталога и маршрутов
---@return any role
local function applied(config, overrides)
    local declared = { config = config, dependencies = { 'roles.httpd' }, routes = routes }

    for key, value in pairs(overrides or {}) do
        declared[key] = value
    end

    local role = framework.new(helper.spec(declared))

    role.apply(nil)

    return role
end

--- Ответ ядра на запрос по пути, с кукой либо без.
---@param path string
---@param cookie string|nil Значение заголовка Cookie
---@param method string|nil Способ; по умолчанию GET
---@param headers table<string, string>|nil Заголовки сверх куки
---@return table response
local function served(path, cookie, method, headers)
    local sent = headers or {}

    sent.cookie = cookie

    return world.server.options.handler(world.server, helper.incoming({ method = method, path = path, headers = sent }))
end

--- Метка из `Set-Cookie`: то, что браузер вернёт следующим запросом.
---@param response table
---@param name string Имя куки
---@return string
local function token_of(response, name)
    return assert(response.headers['set-cookie']:match('^' .. name .. '=([^;]+);'))
end

--- Шифровальщик-двойник: присоединённые данные и base64url вместо шифра.
---
--- Настоящий `tnt-crypto` здесь ни к чему: фреймворк шифровальщик только
--- передаёт драйверу, а шифр проверяют проверки `tnt-session`.
local cipher = {
    encrypt = function(_, text, aad)
        return aad .. '.' .. digest.base64_encode(text, { urlsafe = true })
    end,
    decrypt = function(_, token, aad)
        local body = token:match('^' .. aad .. '%.(.+)$')

        if body == nil then
            return nil, 'чужая кука'
        end

        return digest.base64_decode(body)
    end,
}

g.test_a_section_puts_the_manager_in_the_container_and_its_layer_in_the_web_group = function()
    local role = applied(SESSION)
    local app = role.container()

    t.assert_equals(framework.SESSION, 'session')
    t.assert_equals(framework.WEB, 'web')
    t.assert_equals(app:get('session'):status(), { driver = 'cache', name = 'demo_session', lifetime = 600 })

    -- Слой — в реестре фабрикой, группа web — с ним.
    local declared = testing.module('tnt.framework.session')

    t.assert_equals(declared.groups(app), { web = { 'session' } })
    t.assert_type(declared.layers(app).session, 'function')

    local first = served('/visit')
    local token = token_of(first, 'demo_session')

    t.assert_equals(first.body, '1')
    t.assert_equals(
        first.headers['set-cookie'],
        ('demo_session=%s; Max-Age=600; Path=/; SameSite=Lax; HttpOnly'):format(token)
    )

    -- Второй запрос с этой кукой видит положенное первым.
    local second = served('/visit', 'demo_session=' .. token)

    t.assert_equals(second.body, '2')
    t.assert_equals(token_of(second, 'demo_session'), token)

    -- Хранилище без объявления — кэш приложения: запись лежит в нём.
    t.assert_equals(app:get('cache'):get(token).values, { visits = 2 })

    -- API идёт мимо группы: ни сессии, ни куки.
    local data = served('/data', 'demo_session=' .. token)

    t.assert_equals(data.body, 'nil')
    t.assert_equals(data.headers['set-cookie'], nil)
end

g.test_without_a_section_there_are_no_sessions_and_the_web_group_is_empty = function()
    local role = applied(nil)
    local app = role.container()
    local declared = testing.module('tnt.framework.session')

    t.assert_equals(app:has('session'), false)
    t.assert_equals(declared.groups(app), { web = {} })
    t.assert_equals(declared.layers(app), {})

    -- Маршрут страницы объявлен так же и работает — без сессии и куки.
    local page = served('/visit')

    t.assert_equals(page.body, 'без сессии')
    t.assert_equals(page.headers['set-cookie'], nil)

    -- Слоя нет и в реестре: маршрут, назвавший его, не собирается.
    t.assert_error_msg_contains('слой или группа «session» не объявлены', applied, nil, {
        routes = function(api)
            api.get('/visit', function() end, { middleware = { 'session' } })
        end,
    })

    -- `false` выключает сессии и при разделе.
    local off = applied(SESSION, { session = false })

    t.assert_equals(off.container():has('session'), false)
    t.assert_equals(served('/visit').body, 'без сессии')
end

g.test_a_declaration_alone_brings_sessions_and_the_section_overrides_it_field_by_field = function()
    local cache = testing.module('tnt.cache')
    local store = cache.new({ driver = 'memory', prefix = 'sess:' })

    -- Без раздела довольно объявления; хранилище — его, а не кэш приложения.
    local role = applied(nil, {
        session = { cache = store, name = 'visit', lifetime = 60, cookie = { secure = false, path = '/app' } },
    })

    local first = served('/visit')
    local token = token_of(first, 'visit')

    t.assert_equals(
        first.headers['set-cookie'],
        ('visit=%s; Max-Age=60; Path=/app; SameSite=Lax; HttpOnly'):format(token)
    )
    t.assert_equals(store:get(token).values, { visits = 1 })
    t.assert_equals(role.container():get('cache'):get(token), nil)

    -- Раздел главнее объявления, а настройки куки сливаются по полю:
    -- путь и SameSite — объявления, Secure — раздела. Хранилище здесь —
    -- функцией от контейнера: спейсу и клиенту Redis нужен поднятый узел,
    -- и собирается оно при применении.
    ---@type any
    local built

    applied(SESSION, {
        session = {
            cache = function(app)
                built = cache.new({ driver = 'memory', prefix = app:get('config').instance .. ':' })

                return built
            end,
            name = 'declared',
            cookie = { path = '/app', same_site = 'strict' },
        },
    })

    local merged = served('/visit')
    local again = token_of(merged, 'demo_session')

    t.assert_equals(
        merged.headers['set-cookie'],
        ('demo_session=%s; Max-Age=600; Path=/app; SameSite=Strict; HttpOnly'):format(again)
    )
    t.assert_equals(built:status().prefix, 'router-001-a:')
    t.assert_equals(built:get(again).values, { visits = 1 })
end

g.test_the_cookie_driver_takes_the_cipher_from_the_declaration_and_needs_no_store = function()
    -- Драйвер из раздела, шифровальщик — из объявления; кэша у приложения
    -- нет, и сессиям в куке он не нужен.
    os.setenv('TEST_SESSION_DRIVER', 'cookie')

    local role = applied(SESSION, { cache = false, session = { cipher = cipher } })

    t.assert_equals(role.container():has('cache'), false)
    t.assert_equals(role.container():get('session'):status().driver, 'cookie')

    local token = token_of(served('/visit'), 'demo_session')

    t.assert_str_matches(token, 'demo_session%..+')
    t.assert_equals(served('/visit', 'demo_session=' .. token).body, '2')

    -- Без шифровальщика сборке шифровать нечем.
    t.assert_error_msg_contains(
        'драйверу cookie нужен шифровальщик tnt-crypto',
        applied,
        SESSION
    )
end

g.test_a_cache_driver_without_a_store_is_refused_at_apply = function()
    -- Кэш приложения выключен, своего хранилища объявление не дало:
    -- брать хранилище неоткуда, и это отказ сборки, а не сессия,
    -- которая откажет первым же запросом.
    t.assert_error_msg_equals(
        'приложение test.app не собрано: приложение: session: драйверу cache нужно хранилище — '
            .. 'кэш приложения либо session.cache в объявлении',
        applied,
        SESSION,
        { cache = false }
    )

    os.setenv('TEST_SESSION_DRIVER', 'cache')

    t.assert_error_msg_contains(
        'драйверу cache нужно хранилище',
        applied,
        SESSION,
        { cache = false }
    )

    -- Функция, вернувшая пусто, — ошибка объявления, а не повод молча
    -- увести сессии в кэш приложения.
    local empty = {
        cache = function() end,
    }

    t.assert_error_msg_contains(
        'сессия: драйверу cache нужно хранилище tnt-cache',
        applied,
        SESSION,
        { session = empty }
    )
end

g.test_unknown_fields_of_the_declaration_and_the_section_are_refused = function()
    -- Объявление — при загрузке роли, раздел — при применении.
    t.assert_error_msg_equals(
        'приложение: session: ключа «lifetme» нет, есть cache, cipher, cookie, driver, lifetime, name',
        framework.new,
        helper.spec({ session = { lifetme = 60 } })
    )
    t.assert_error_msg_equals(
        'приложение: session должно быть table или false, получено string',
        framework.new,
        helper.spec({ session = 'yes' })
    )

    -- Шифровальщик — не настройка: разделу его не передать.
    os.setenv('TEST_SESSION_CIPHER', 'secret')

    t.assert_error_msg_equals(
        'приложение test.app не собрано: приложение: раздел session: ключа «cipher» нет, '
            .. 'есть cookie, driver, lifetime, name',
        applied,
        SESSION
    )
end

g.test_the_layer_takes_the_manager_the_build_left_in_the_container = function()
    -- Слой собирается после провайдеров и `build`: менеджер, подменённый
    -- ими, и встаёт в слой.
    local session = testing.module('tnt.session')

    applied(SESSION, {
        build = function(app)
            app:replace('session', session.new({ cache = app:get('cache'), name = 'replaced' }))
        end,
    })

    t.assert_str_matches(served('/visit').headers['set-cookie'], 'replaced=.+')
end

--- Маршруты своих слоёв и групп: форма под группой web со сверкой
--- токена, крюк, освобождённый от сверки, и данные под группой api.
---@param api table Роутер приложения
local function guarded(api)
    local router = testing.module('tnt.router')

    api.get('/form', function(request)
        return router.text(request.session:token())
    end, { middleware = { framework.WEB } })

    api.post('/form', function()
        return router.text('принято')
    end, { middleware = { framework.WEB } })

    api.post('/hooks/pay', function()
        return router.text('крюк')
    end, { middleware = { framework.WEB } })

    api.get('/items', function()
        return router.text('данные')
    end, { middleware = { 'api' } })
end

g.test_own_layers_and_groups_reach_the_registry_and_web_takes_csrf_after_the_session = function()
    local session = testing.module('tnt.session')

    -- Группы — таблицей, которую проверка видит и после применения.
    local groups = {
        web = { session.csrf.new({ except = { '/hooks' } }) },
        api = { { 'throttle', { per_minute = 1 } } },
    }

    local role = applied(SESSION, {
        routes = guarded,
        -- Ограничителю нужна служба из контейнера — слои функцией от него.
        layers = function(app)
            return { throttle = app:get('throttle'):factory() }
        end,
        groups = groups,
    })

    -- Слой сессий встал первым в копию группы: объявление приложения
    -- нетронуто, и следующее применение не допишет его второй раз.
    local declared = testing.module('tnt.framework.session')

    t.assert_equals(groups.web, { groups.web[1] })
    t.assert_equals(declared.groups(role.container(), groups), {
        web = { 'session', groups.web[1] },
        api = groups.api,
    })

    -- POST без токена — отказ сверки 403, а не бросок «слой csrf ставят
    -- после слоя session»: сессия в запросе к сверке уже есть.
    local refused = served('/form', nil, 'POST')

    t.assert_equals(refused.status, 403)
    t.assert_equals(
        require('json').decode(refused.body),
        { error = 'запрос не подтверждён токеном' }
    )

    -- Токен со страницы и кука её сессии — принято.
    local page = served('/form')
    local cookie = 'demo_session=' .. token_of(page, 'demo_session')
    local token = tostring(page.body)

    t.assert_equals(served('/form', cookie, 'POST', { ['x-csrf-token'] = token }).body, 'принято')

    -- Освобождённый адрес сверки не проходит.
    t.assert_equals(served('/hooks/pay', nil, 'POST').body, 'крюк')

    -- Маршрут группы api проходит свой слой — второй запрос за минуту
    -- получает 429, — а сессии и куки у него нет.
    local first = served('/items')

    t.assert_equals(first.body, 'данные')
    t.assert_equals(first.headers['x-ratelimit-limit'], '1')
    t.assert_equals(first.headers['set-cookie'], nil)
    t.assert_equals(served('/items').status, 429)
end

g.test_without_sessions_the_web_group_is_the_application_own = function()
    -- Группы — функцией от контейнера, слои — таблицей.
    local stamp = function(options)
        return function(request, nxt)
            local response = nxt(request)

            response.headers['x-stamp'] = options.mark

            return response
        end
    end

    local role = applied(nil, {
        layers = { stamp = stamp },
        groups = function(app)
            return { web = { { 'stamp', { mark = app:get('config').instance } } } }
        end,
    })

    local page = served('/visit')

    t.assert_equals(page.body, 'без сессии')
    t.assert_equals(page.headers['x-stamp'], 'router-001-a')
    t.assert_equals(served('/data').headers['x-stamp'], nil)

    -- Функция, не отдавшая ничего, — своих слоёв и групп нет.
    local declared = testing.module('tnt.framework.session')
    local app = role.container()

    t.assert_equals(declared.layers(app, function() end), {})
    t.assert_equals(declared.groups(app, function() end), { web = {} })
end

g.test_the_name_session_stays_the_framework_own = function()
    local pass = function(request, nxt)
        return nxt(request)
    end

    local own = function()
        return pass
    end

    -- Свой слой под именем слоя сессий — отказ и при сессиях, и без них:
    -- включённые разделом, они молча подменили бы слой приложения.
    local taken = 'приложение test.app не собрано: приложение: слой session ставит фреймворк — '
        .. "свой слой назовите иначе, а менеджер сессий подменяют через app:replace('session', …)"

    t.assert_error_msg_equals(taken, applied, SESSION, { layers = { session = own } })
    t.assert_error_msg_equals(taken, applied, nil, { layers = { session = own } })

    -- Группа web, назвавшая слой сессий сама, — именем либо записью
    -- с параметрами: второй слой в ней вёл бы вторую сессию.
    local twice = 'приложение test.app не собрано: приложение: группа web: слой session фреймворк '
        .. 'ставит в неё сам, первым, — назовите в ней только свои слои'

    t.assert_error_msg_equals(twice, applied, SESSION, { groups = { web = { 'session' } } })
    t.assert_error_msg_equals(twice, applied, SESSION, { groups = { web = { { 'session', { field = 'visitor' } } } } })

    -- Своя группа вправе взять слой сессий именем и поставить его, где
    -- ей нужно: правило «сессия первой» — только у группы web.
    applied(SESSION, {
        groups = { page = { pass, 'session' } },
        routes = function(api)
            api.get('/page', function(request)
                return testing.module('tnt.router').text(tostring(request.session ~= nil))
            end, { middleware = { 'page' } })
        end,
    })

    t.assert_equals(served('/page').body, 'true')
end

g.test_layers_and_groups_of_a_wrong_kind_are_refused = function()
    -- Вид поля — при загрузке роли, словом фреймворка: ядру уходит его
    -- функция, и поля приложения ядро не увидит.
    t.assert_error_msg_equals(
        'приложение: layers должно быть table или function, получено string',
        framework.new,
        helper.spec({ layers = 'session' })
    )
    t.assert_error_msg_equals(
        'приложение: groups должно быть table или function, получено boolean',
        framework.new,
        helper.spec({ groups = true })
    )

    -- Что отдала функция и группа web не списком — отказ реестра при сборке.
    t.assert_error_msg_contains('слои объявляются таблицей, а не string', applied, SESSION, {
        layers = function()
            return 'csrf'
        end,
    })
    t.assert_error_msg_contains(
        'группы объявляются таблицей, а не number',
        applied,
        SESSION,
        {
            groups = function()
                return 7
            end,
        }
    )
    t.assert_error_msg_contains(
        'группа «web» объявляется списком записей, а не string',
        applied,
        SESSION,
        { groups = { web = 'csrf' } }
    )
end

-- ─── Токен формы в данных страниц ───────────────────────────────────────────

--- Каталог страниц проверки: заводится ею, убирается после неё.
---@type string|nil
local pages

--- Сервер `http.server` живой проверки: поднимается ею, гасится после неё.
---@type table|nil
local httpd

g.after_each(function()
    if httpd ~= nil then
        httpd:stop()
        httpd = nil
    end

    if pages ~= nil then
        require('fio').rmtree(pages)
        pages = nil
    end
end)

--- Кладёт страницы проверки в свежий каталог и отдаёт его.
---
--- Форма пишет токен директивой `@csrf`, а обработчик о нём не знает:
--- токен обязан прийти общими данными страниц.
---@return string
local function views()
    local fio = require('fio')
    local sources = {
        form = '<form method="post" action="/form">@csrf<input name="name" value="{{ name }}"></form>',
        plain = '<p>{{ title }}</p>',
        shared = '{{ who }}/{{ where }}/{{ csrf_token }}',
    }

    pages = fio.tempdir()

    for name, source in pairs(sources) do
        testing.write_file(fio.pathjoin(pages, name .. '.thtml.lua'), source)
    end

    return pages
end

--- Маршруты страниц: форма под группой web, её приём, страница с общими
--- данными и страница API мимо группы.
---@param api table Роутер приложения
local function form_routes(api)
    local router = testing.module('tnt.router')
    local web = { middleware = { framework.WEB } }

    api.get('/form', function()
        return api.view('form', { name = 'Иван' })
    end, web)

    api.post('/form', function(request)
        return router.text('принято: ' .. request.form.name)
    end, web)

    api.get('/shared', function()
        return api.view('shared', { where = 'обработчик' })
    end, web)

    api.get('/api/page', function()
        return api.view('plain', { title = 'без сессии' })
    end)
end

--- Объявление страниц проверки: каталог, маршруты и сверка токена
--- в группе web — так, как её кладёт приложение, после слоя сессий.
---
--- Сверка спрашивает токен только у POST, PUT, PATCH и DELETE: показу
--- страницы без сессий она не мешает.
---@param overrides table|nil Поля объявления сверх страниц
---@return table
local function forms(overrides)
    local declared = {
        views = views(),
        routes = form_routes,
        groups = { [framework.WEB] = { testing.module('tnt.session').csrf.new() } },
    }

    for key, value in pairs(overrides or {}) do
        declared[key] = value
    end

    return declared
end

--- Отправка формы тем же обработчиком, который ядро поставило на сервер.
---@param cookie string|nil Значение заголовка Cookie
---@param body string Тело формы
---@return table response
local function posted(cookie, body)
    return world.server.options.handler(
        world.server,
        helper.incoming({
            method = 'POST',
            path = '/form',
            body = body,
            headers = { cookie = cookie, ['content-type'] = 'application/x-www-form-urlencoded' },
        })
    )
end

--- Значение скрытого поля `_token` на странице.
---@param page string
---@return string
local function field_of(page)
    local field = assert(page:match('<input type="hidden" name="_token" value="([^"]+)">'))

    return field
end

g.test_a_page_of_the_web_group_gets_the_token_without_naming_it = function()
    local role = applied(SESSION, forms())

    local form = served('/form')
    local id = token_of(form, 'demo_session')
    local field = field_of(form.body)

    t.assert_equals(form.status, 200)
    t.assert_equals(
        form.body,
        ('<form method="post" action="/form"><input type="hidden" name="_token" value="%s">'):format(field)
            .. '<input name="name" value="Иван"></form>'
    )

    -- Токен на странице — токен сессии: он и лёг в хранилище вместе с ней.
    t.assert_equals(role.container():get('cache'):get(id).token, field)

    -- Поле формы проходит сверку слоя csrf, а без него форма — отказ 403.
    local accepted = posted('demo_session=' .. id, '_token=' .. field .. '&name=Anna')

    t.assert_equals(accepted.status, 200)
    t.assert_equals(accepted.body, 'принято: Anna')
    t.assert_equals(posted('demo_session=' .. id, 'name=Anna').status, 403)
end

g.test_a_page_outside_the_web_group_is_drawn_without_a_session = function()
    -- У маршрута API сессии нет: общие данные — пустая таблица, а не бросок.
    applied(SESSION, forms())

    local page = served('/api/page')

    t.assert_equals(page.status, 200)
    t.assert_equals(page.body, '<p>без сессии</p>')
    t.assert_equals(page.headers['set-cookie'], nil)
end

g.test_the_data_of_the_application_lie_over_the_token_and_under_the_handler = function()
    -- Функция от контейнера зовётся на сборке, её функция от запроса —
    -- на каждой странице; заголовок проверки подменяет токен приложением.
    local role = applied(
        SESSION,
        forms({
            view_data = function(app)
                local instance = app:get('config').instance

                return function(request)
                    return {
                        who = instance,
                        where = 'приложение',
                        csrf_token = request.headers['x-own-token'],
                    }
                end
            end,
        })
    )

    local page = served('/shared')
    local token = role.container():get('cache'):get(token_of(page, 'demo_session')).token

    t.assert_equals(page.body, ('router-001-a/обработчик/%s'):format(token))

    local own = world.server.options.handler(
        world.server,
        helper.incoming({ path = '/shared', headers = { ['x-own-token'] = 'свой' } })
    )

    t.assert_equals(own.body, 'router-001-a/обработчик/свой')
end

g.test_the_data_of_the_application_come_alone_without_sessions = function()
    -- Сессий нет — токена нет, а данные приложения доходят как есть.
    applied(
        nil,
        forms({
            view_data = function()
                return function()
                    return { who = 'приложение', csrf_token = 'без сессии' }
                end
            end,
        })
    )

    t.assert_equals(served('/shared').body, 'приложение/обработчик/без сессии')

    -- Без сессий и без данных приложения общих данных нет вовсе.
    local declared = testing.module('tnt.framework.session')

    t.assert_equals(declared.view_data(applied(nil, { views = views() }).container()), nil)
end

g.test_a_refusal_of_the_application_data_reaches_the_router_as_is = function()
    -- Отказ парой — ответ по договору отказа, не таблица — поломка словом
    -- роутера; токен при этом не заводится.
    local answers = {
        ['/shared'] = { nil, { status = 403, message = 'страница закрыта' } },
        ['/api/page'] = { nil },
    }

    applied(
        SESSION,
        forms({
            view_data = function()
                return function(request)
                    return unpack(answers[request.path])
                end
            end,
        })
    )

    local refused = served('/shared')

    -- Сессия нетронута: ни токена в хранилище, ни куки новому посетителю.
    t.assert_equals(refused.status, 403)
    t.assert_str_contains(refused.body, 'страница закрыта')
    t.assert_equals(refused.headers['set-cookie'], nil)
    t.assert_equals(served('/api/page').status, 500)

    -- Не функция от запроса — отказ сборки, а не бросок на первой странице.
    t.assert_error_msg_equals(
        'приложение test.app не собрано: приложение: view_data должна отдать функцию от запроса, получено table',
        applied,
        SESSION,
        {
            view_data = function()
                return { csrf_token = 'одно на всех' }
            end,
        }
    )
    t.assert_error_msg_equals(
        'приложение: view_data должно быть function, получено string',
        framework.new,
        helper.spec({ view_data = 'csrf' })
    )
end

g.test_a_form_sent_by_a_real_client_passes_the_check = function()
    -- Живой сервер `http.server` и клиент HTTP: кука и поле формы идут
    -- сокетом, как из браузера, а обработчик о токене не знает.
    local http_client = require('http.client')

    httpd = require('http.server').new('127.0.0.1', 0, { log_requests = false, log_errors = false })
    httpd:start()
    world.server = httpd

    applied(SESSION, forms())

    local address = ('http://127.0.0.1:%d/form'):format(httpd.tcp_server:name().port)
    local client = http_client.new()
    local form = client:request('GET', address, nil, { timeout = 5 })
    local cookie = 'demo_session=' .. token_of(form, 'demo_session')
    local headers = { cookie = cookie, ['content-type'] = 'application/x-www-form-urlencoded' }

    t.assert_equals(form.status, 200)

    local accepted = client:request(
        'POST',
        address,
        '_token=' .. field_of(form.body or '') .. '&name=Anna',
        { timeout = 5, headers = headers }
    )

    t.assert_equals(accepted.status, 200)
    t.assert_equals(accepted.body, 'принято: Anna')
    t.assert_equals(client:request('POST', address, 'name=Anna', { timeout = 5, headers = headers }).status, 403)
end
