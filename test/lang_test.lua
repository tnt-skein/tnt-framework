--- Проверки переводов приложения: каталог `lang/`, язык по умолчанию,
--- директивы страниц и слой языка запроса на входе роутера.
---
--- Ядро Tarantool здесь не поднимается, как и в остальных проверках
--- раскладки: конфигурация и роль сервера — двойники мира ядра.

local json = require('json')
local t = require('luatest')

local helper = dofile('test/helper.lua')
local testing = helper.testing

local g = t.group('tnt.framework.lang')

--- Записи журнала: ядро пишет о сборке.
local trap = testing.capture_log()

--- Корень образца с двумя языками.
local APP = helper.path('app_with_lang')

--- Каталог настроек с разделом `app`, но без `app.locale`.
local NO_LOCALE = helper.path('config_app')

---@type TntKernelWorld
local world

---@type any
local framework

g.before_each(function()
    world = helper.world()
    framework = helper.load(world)
    trap.forget()
end)

g.after_each(function()
    helper.forget_globals()
    helper.unload()
end)

g.after_all(trap.release)

--- Ответ собранного приложения на запрос по адресу.
---@param path string
---@param headers table|nil
---@return table
local function served(path, headers)
    return world.server.options.handler(world.server, helper.incoming({ path = path, headers = headers }))
end

--- Ответ собранного приложения на запрос страницы.
---@param headers table|nil
---@return table
local function page(headers)
    return served('/', headers)
end

--- Роль образца с нужными полями поверх соглашения.
---@param fields table|nil
---@return any
local function role_of(fields)
    local declared = { dependencies = { 'roles.httpd' }, base = APP }

    for key, value in pairs(fields or {}) do
        declared[key] = value
    end

    return framework.new(helper.spec(declared))
end

g.test_the_lang_directory_brings_the_translator_the_directives_and_the_layer = function()
    local role = role_of()

    t.assert_equals(role.layout().lang, APP .. '/lang')

    role.apply(nil)

    local lang = role.container():get('i18n')

    t.assert_equals(lang:locales(), { 'en', 'ru' })
    t.assert_equals(lang:locale(), 'ru')

    local russian = page()

    t.assert_equals(
        russian.body,
        '<html lang="ru"><title>Главная</title><p>5 узлов</p><p>missing.key</p></html>\n'
    )
    t.assert_equals(russian.headers['content-language'], 'ru')
    t.assert_equals(russian.headers.vary, 'Accept-Language')

    local english = page({ ['accept-language'] = 'en-US,en;q=0.9,ru;q=0.5' })

    t.assert_equals(english.body, '<html lang="en"><title>Home</title><p>5 nodes</p><p>missing.key</p></html>\n')
    t.assert_equals(english.headers['content-language'], 'en')
end

g.test_the_default_language_is_the_setting_app_locale = function()
    os.setenv('TEST_LOCALE', 'en')

    local role = role_of()

    role.apply(nil)
    os.setenv('TEST_LOCALE', nil)

    t.assert_equals(role.container():get('i18n'):locale(), 'en')
    t.assert_str_contains(page().body, '<title>Home</title>')
end

g.test_several_languages_without_a_default_one_are_refused = function()
    local role = role_of({ config = NO_LOCALE })

    t.assert_error_msg_equals(
        'приложение test.app не собрано: приложение: переводы: в '
            .. APP
            .. '/lang языков несколько (en, ru) — '
            .. 'назовите язык по умолчанию настройкой app.locale',
        role.apply,
        nil
    )
end

g.test_a_single_language_is_the_default_one = function()
    local role = role_of({ config = NO_LOCALE, lang = helper.path('lang_single') })

    role.apply(nil)

    t.assert_equals(role.container():get('i18n'):locales(), { 'ru' })
    t.assert_equals(role.container():get('i18n'):locale(), 'ru')
end

g.test_no_translations_mean_no_translator = function()
    for _, lang in ipairs({ false, helper.path('lang_empty') }) do
        local role = role_of({ lang = lang })

        t.assert_equals(role.layout().lang, nil)

        role.apply(nil)

        t.assert_equals(role.container():has('i18n'), false)
        t.assert_equals(page().headers['content-language'], nil)

        helper.forget_globals()
        helper.unload()
        world = helper.world()
        framework = helper.load(world)
    end
end

g.test_unfit_translations_are_refused_at_the_assembly = function()
    local broken = role_of({ lang = helper.path('lang_broken') })

    t.assert_error_msg_contains(
        'приложение: переводы: файл настроек '
            .. helper.path('lang_broken/ru.lua')
            .. ' не разобран',
        broken.apply,
        nil
    )

    local invalid = role_of({ lang = helper.path('lang_invalid') })

    t.assert_error_msg_equals(
        'приложение test.app не собрано: приложение: переводы: строка nodes языка ru: форм 2, а у языка их 3',
        invalid.apply,
        nil
    )

    t.assert_error_msg_equals(
        'приложение: lang должно быть string или false, получено number',
        framework.new,
        helper.spec({ lang = 7 })
    )
end

g.test_the_build_may_replace_the_translator_and_the_pages_follow = function()
    local i18n = testing.module('tnt.i18n')
    local role = role_of({
        build = function(app)
            app:replace(
                'i18n',
                i18n.new({
                    locale = 'ru',
                    messages = {
                        ru = {
                            home = { title = 'Своя главная' },
                            nodes = { 'узел', 'узла', 'узлов' },
                        },
                    },
                })
            )
        end,
    })

    role.apply(nil)

    t.assert_equals(
        page().body,
        '<html lang="ru"><title>Своя главная</title><p>узлов</p><p>missing.key</p></html>\n'
    )
end

g.test_a_refusal_speaks_the_language_of_the_request = function()
    role_of().apply(nil)

    -- Промах по адресу: у отказа роутера кода нет, и слово ищется
    -- по статусу — строкой `errors.404`.
    local english = served('/nope', { ['accept-language'] = 'en' })

    t.assert_equals(english.status, 404)
    t.assert_equals(json.decode(english.body).error, 'No such address')
    t.assert_equals(english.headers['content-language'], 'en')
    t.assert_equals(english.headers.vary, 'Accept-Language')

    -- По-русски строки `errors.404` нет — говорит слово самого роутера.
    local russian = served('/nope')

    t.assert_equals(json.decode(russian.body).error, 'нет такого адреса')
    t.assert_equals(russian.headers['content-language'], 'ru')
    t.assert_equals(russian.headers.vary, 'Accept-Language')

    -- Браузер получает то же слово на странице.
    local shown = served('/nope', { ['accept-language'] = 'en', accept = 'text/html' })

    t.assert_equals(shown.headers['content-type'], 'text/html; charset=utf-8')
    t.assert_str_contains(shown.body, '<p>No such address</p>')
    t.assert_equals(shown.headers['content-language'], 'en')

    -- Отказ обработчика — по своему коду, и строка приложения главнее
    -- слова обработчика на любом языке.
    local unfit = served('/orders/7', { ['accept-language'] = 'en' })

    t.assert_equals(unfit.status, 422)
    t.assert_equals(json.decode(unfit.body).error, 'The order did not fit')
    t.assert_equals(unfit.headers['content-language'], 'en')
    t.assert_equals(json.decode(served('/orders/7').body).error, 'Заказ не подошёл')
end

g.test_without_translations_a_refusal_keeps_its_own_word = function()
    role_of({ lang = false }).apply(nil)

    local answer = served('/nope', { ['accept-language'] = 'en' })

    t.assert_equals(json.decode(answer.body).error, 'нет такого адреса')
    t.assert_equals(answer.headers['content-language'], nil)
    t.assert_equals(answer.headers.vary, nil)
end

g.test_the_word_of_a_refusal_is_looked_up_by_code_then_in_the_default_language = function()
    local i18n = testing.module('tnt.i18n')
    local errors = testing.module('tnt.error')
    local context = testing.module('tnt.context')
    local lang = i18n.new({
        locale = 'ru',
        messages = {
            ru = {
                errors = {
                    both = 'Оба',
                    home = 'Только по-русски',
                    internal = 'Сломалось: {incident}',
                },
            },
            en = {
                errors = {
                    both = 'Both',
                    away = 'Only in English: {id}',
                    ['404'] = 'No such address',
                    internal = 'Broke: {incident}',
                },
            },
        },
    })
    local translate = testing.module('tnt.framework.lang').refusals(function()
        return lang
    end)
    local catalog = errors.registry()

    for _, code in ipairs({ 'both', 'home', 'away', 'none' }) do
        catalog:define(code, { status = 422, message = 'Слово ' .. code })
    end

    -- Запрос с языком, но вне слоя: контекст пуст, язык — в запросе.
    local english = { locale = 'en' }

    t.assert_equals({ translate(catalog:new('both'), english) }, { 'Both', 'en' })
    t.assert_equals({ translate(catalog:new('away', { id = 7 }), english) }, { 'Only in English: 7', 'en' })
    -- Строка языка по умолчанию — тоже строка приложения, и она главнее
    -- слова отказа; нет её нигде — перевода нет.
    t.assert_equals({ translate(catalog:new('home'), english) }, { 'Только по-русски', 'en' })
    t.assert_equals({ translate(catalog:new('none'), english) }, {})
    -- Строка только на другом языке запросу по-русски не годится.
    t.assert_equals({ translate(catalog:new('away'), { locale = 'ru' }) }, {})

    -- Отказ без кода ищется по статусу; отказ с кодом — нет.
    t.assert_equals({ translate(catalog:of({ status = 404 }), english) }, { 'No such address', 'en' })
    t.assert_equals({ translate(catalog:of({ status = 404, code = 'gone' }), english) }, {})

    -- Опознаватель встаёт в слово внутренней поломки.
    local broken = catalog:internal('соединение порвано')

    t.assert_equals({ translate(broken, english) }, { 'Broke: ' .. broken.incident, 'en' })

    -- Без языка в запросе — язык контекста, а без него — по умолчанию;
    -- язык в запросе главнее контекста.
    t.assert_equals({ translate(catalog:new('both')) }, { 'Оба', 'ru' })
    t.assert_equals({ translate(catalog:new('both'), { locale = 'не метка' }) }, { 'Оба', 'ru' })

    context.run({ [i18n.CONTEXT_KEY] = 'en' }, function()
        t.assert_equals({ translate(catalog:new('both'), 'не запрос') }, { 'Both', 'en' })
        t.assert_equals({ translate(catalog:new('both'), { locale = 'RU' }) }, { 'Оба', 'ru' })
    end)
end
