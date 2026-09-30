--- Объявление приложения на фреймворке: набор полей и виды своих полей.
---
--- Ошибка здесь — ошибка программиста, и падает она при загрузке модуля
--- роли: ядро покажет её в alerts на первом же применении, а не
--- на первом запросе в бою. Вид полей, которые уходят ядру как есть,
--- проверяет ядро своим правилом (`tnt.kernel.spec`), тем же ладом.

local cors = require('tnt.framework.cors')
local sessions = require('tnt.framework.session')

--- Отказ без места вызова: текст уходит оператору в alerts.
local fail = require('tnt.must.fail').raise

--- Проверки по имени без броска: отсюда текст отказа о незнакомом поле,
--- общий со всеми пакетами, а бросок — свой, без места.
local explain = require('tnt.must').explain

local Module = {}

--- Поля объявления — те, что в таблице `docs/framework.md`.
---
--- Незнакомое поле отвергается здесь, хотя ядро отвергло бы его и само:
--- в отказе ядро назвало бы свои поля — без каталогов фреймворка, зато
--- с `entry`, `view`, `error_page` и `error_translate`, которые ядру
--- собирает сам фреймворк, — и отказ послал бы искать не туда. Заданные
--- приложением, они молча пропадали бы, поэтому их здесь нет. `layers`,
--- `groups` и `view_data` есть: фреймворк отдаёт их ядру вместе со своими
--- — слоем сессий и токеном формы (`tnt.framework.session`). Значения
--- описаны как любые (`'?'`): вид своих полей фреймворк проверяет ниже,
--- остальных — ядро, тем же ладом.
local FIELDS = {
    name = '?',
    base = '?',
    prefix = '?',
    dependencies = '?',
    schema = '?',
    config = '?',
    providers = '?',
    migrations = '?',
    seeders = '?',
    models = '?',
    build = '?',
    middleware = '?',
    layers = '?',
    groups = '?',
    downtime = '?',
    views = '?',
    lang = '?',
    public = '?',
    cache = '?',
    throttle = '?',
    files = '?',
    session = '?',
    cors = '?',
    config_cache = '?',
    views_compiled = '?',
    routes = '?',
    iproto = '?',
    ready = '?',
    health_check = '?',
    view_data = '?',
}

--- Поля, которые бывают своего вида либо `false` — «выключено».
local OPTIONAL = {
    cache = 'table',
    throttle = 'table',
    files = 'table',
    session = 'table',
    cors = 'table',
    views = 'string',
    lang = 'string',
}

--- Проверенное объявление приложения — в части, которую ядро не видит.
---
--- Набор полей и виды каталогов и списков, которые превращаются
--- в функции, проверяются здесь; вид остальных полей — у ядра, его
--- правилом.
---@param spec any
function Module.checked(spec)
    if type(spec) ~= 'table' then
        fail('приложение объявляется таблицей')
    end

    local stray = explain.options(spec, 'приложение', FIELDS)

    if stray ~= nil then
        fail(stray)
    end

    for key, kind in pairs({
        base = 'string',
        prefix = 'string',
        config = 'string',
        config_cache = 'string',
        views_compiled = 'string',
        migrations = 'string',
        seeders = 'string',
        build = 'function',
        ready = 'function',
        view_data = 'function',
    }) do
        if spec[key] ~= nil and type(spec[key]) ~= kind then
            fail(
                ('приложение: %s должно быть %s, получено %s'):format(
                    key,
                    kind,
                    type(spec[key])
                )
            )
        end
    end

    for key, kind in pairs(OPTIONAL) do
        if spec[key] ~= nil and spec[key] ~= false and type(spec[key]) ~= kind then
            fail(
                ('приложение: %s должно быть %s или false, получено %s'):format(
                    key,
                    kind,
                    type(spec[key])
                )
            )
        end
    end

    -- Поля сессий — при загрузке, как и поля самого объявления:
    -- `tnt-session` лишних полей не разбирает, и опечатка молча ушла бы
    -- в умолчание.
    if type(spec.session) == 'table' then
        sessions.checked(spec.session)
    end

    -- Поля слоя межсайтовых запросов — тем же ладом: целиком слой
    -- собирается при применении, когда источники уже пришли разделом.
    if type(spec.cors) == 'table' then
        cors.checked(spec.cors)
    end

    if
        spec.public ~= nil
        and spec.public ~= false
        and type(spec.public) ~= 'string'
        and type(spec.public) ~= 'table'
    then
        fail(
            ('приложение: public должно быть string, table или false, получено %s'):format(
                type(spec.public)
            )
        )
    end

    if
        spec.downtime ~= nil
        and spec.downtime ~= false
        and type(spec.downtime) ~= 'string'
        and type(spec.downtime) ~= 'table'
    then
        fail(
            ('приложение: downtime должно быть string, table или false, получено %s'):format(
                type(spec.downtime)
            )
        )
    end

    -- Свои слои и группы реестра — таблицей либо функцией от контейнера,
    -- как у ядра. Ядро их вида не увидит: ему уходит функция фреймворка,
    -- которая кладёт их в реестр рядом со слоем сессий.
    for _, key in ipairs({ 'layers', 'groups' }) do
        if spec[key] ~= nil and type(spec[key]) ~= 'table' and type(spec[key]) ~= 'function' then
            fail(
                ('приложение: %s должно быть table или function, получено %s'):format(
                    key,
                    type(spec[key])
                )
            )
        end
    end

    if spec.providers ~= nil and type(spec.providers) ~= 'string' and type(spec.providers) ~= 'table' then
        fail(
            ('приложение: providers должно быть table, получено %s'):format(
                type(spec.providers)
            )
        )
    end
end

return Module
