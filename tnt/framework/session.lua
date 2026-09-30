--- Сессии приложения по разделу настроек `session` (`tnt-session`).
---
---     config/session.lua    session    менеджер tnt-session; слой session — в группе web
---
--- Раздел несёт то, что пишется строкой и числом: драйвер, имя куки,
--- срок и настройки куки. Хранилище кэша и шифровальщик — не настройки,
--- и в раздел их не положить: их дают объявлением приложения —
--- `session = { cache = store }` либо `{ driver = 'cookie', cipher = cipher }`.
--- Хранилищу, которому нужно что-то из контейнера, — клиент Redis
--- приложения, — объявление даёт функцию от контейнера: она зовётся
--- при применении, а при загрузке роли клиента ещё нет. Хранилищу
--- на спейсе по имени функция не нужна: спейс оно ищет первым
--- обращением, а заводит его шаг миграции уже после применения.
--- Драйверу `cache` без своего хранилища достаётся кэш приложения:
--- раздел `cache` уводит в Redis и кэш, и сессии одной настройкой.
---
--- Без раздела и без объявления сессий нет — ни менеджера, ни слоя:
--- сессия — это кука у каждого посетителя, и ставить её приложению,
--- которое о ней не просило, нельзя. `session = false` выключает сессии
--- и при разделе.
---
--- Слой `session` объявляется в реестре слоёв приложения фабрикой
--- менеджера и стоит в группе `web`: маршруты страниц берут группу
--- именем, а API идёт мимо — у сценария куки нет, и сессия ему ни к чему.
--- Группа есть и без сессий, пустая: маршрут страницы объявляется
--- одинаково при любом разделе, а выключенные сессии не роняют сборку.
---
--- Свои слои и группы приложение объявляет полями `layers` и `groups`,
--- и в реестр они ложатся рядом со слоем сессий. Группа `web` приложения
--- дописывается после `session`: сверка токена (`csrf`) берёт сессию
--- из запроса, и порядок «сессия, потом сверка» задан одним правилом,
--- а не заботой каждого маршрута. Имя `session` у приложения занято
--- всегда, есть сессии или нет: иначе включённые разделом сессии молча
--- подменили бы свой слой приложения либо легли бы в группу вторым
--- слоем с другой сессией.
---
--- Токен формы кладётся в данные каждой страницы сам — общими данными
--- страниц роутера (`view_data`): директива `@csrf` ждёт его полем
--- `csrf_token`, и носи его каждый обработчик сам, забытый нашёлся бы
--- только ответом 500 на показе страницы. Кладётся он, только когда
--- сессия в запросе есть: маршрут API идёт мимо группы `web`, и его
--- странице достаётся пустая таблица, а не бросок.

local session = require('tnt.session')
local template = require('tnt.template')

local services = require('tnt.framework.services')

--- Отказ без места вызова: текст уходит оператору в alerts.
local fail = require('tnt.must.fail').raise

--- Проверки по имени без броска: текст отказа общий со всеми пакетами.
local explain = require('tnt.must').explain

local Module = {}

--- Имя менеджера в контейнере — оно же имя слоя в реестре.
Module.NAME = 'session'

--- Группа слоёв страниц.
Module.WEB = 'web'

--- Что пишется разделом настроек: строки, числа и таблица куки.
local SECTION = { driver = '?', name = '?', lifetime = '?', cookie = '?' }

--- Что пишется объявлением: сверх раздела — хранилище и шифровальщик.
local DECLARED = { driver = '?', name = '?', lifetime = '?', cookie = '?', cache = '?', cipher = '?' }

---@class TntFrameworkSessionSpec Объявление сессий: настройки `tnt-session`, хранилище и шифровальщик
---@field driver string|TntSessionDriver|nil `cache` (по умолчанию), `cookie` либо свой драйвер
---@field cache TntCacheStore|(fun(app: TntDiContainer): TntCacheStore)|nil Хранилище либо функция от контейнера
---@field cipher TntSessionCipher|nil Шифровальщик `tnt-crypto` — для драйвера `cookie`
---@field name string|nil Имя куки; по умолчанию `tnt_session`
---@field lifetime integer|nil Сколько живёт сессия, секунды; по умолчанию два часа
---@field cookie table|nil Настройки куки `tnt-cookie`: path, domain, secure, same_site

--- Отказ, когда драйверу `cache` брать хранилище неоткуда.
local NO_STORE = 'приложение: session: драйверу cache нужно хранилище — '
    .. 'кэш приложения либо session.cache в объявлении'

--- Отказ: приложение объявило свой слой под именем слоя сессий.
local OWN_SESSION = 'приложение: слой session ставит фреймворк — свой слой назовите иначе, '
    .. "а менеджер сессий подменяют через app:replace('session', …)"

--- Отказ: группа `web` приложения назвала слой сессий сама.
local WEB_SESSION = 'приложение: группа web: слой session фреймворк ставит в неё сам, первым, — '
    .. 'назовите в ней только свои слои'

--- Бросает отказ описания, если он есть.
---@param complaint string|nil
local function demand(complaint)
    if complaint ~= nil then
        fail(complaint)
    end
end

--- Проверяет поля объявления сессий.
---
--- Зовётся при загрузке роли: `tnt-session` лишних полей не разбирает,
--- и `lifetme = 60` молча оставило бы сессию на два часа.
---@param declared table
function Module.checked(declared)
    demand(explain.options(declared, 'приложение: session', DECLARED))
end

--- Две таблицы в одну: у верхней последнее слово.
---@param below table
---@param above table
---@return table
local function over(below, above)
    local merged = {}

    for _, source in ipairs({ below, above }) do
        for key, value in pairs(source) do
            merged[key] = value
        end
    end

    return merged
end

--- Настройки менеджера: объявление, поверх него — раздел.
---
--- Настройки куки сливаются по полю, а не целиком: домен куки даёт
--- объявление, а `secure = false` стенда без TLS — раздел из окружения,
--- и одно не должно затирать другое.
---
--- Драйвер `cache` — умолчание `tnt-session`, и без драйвера в настройках
--- хранилище нужно так же. Кэш приложения берётся при сборке: подменять
--- его провайдером после этого поздно, своё хранилище сессиям дают
--- объявлением. Хранилище функцией собирается здесь же, из контейнера
--- этого применения.
---@param app TntDiContainer
---@param declared table
---@param section table
---@return TntSessionOptions
local function options_of(app, declared, section)
    local options = over(declared, section)

    if type(declared.cookie) == 'table' and type(section.cookie) == 'table' then
        options.cookie = over(declared.cookie, section.cookie)
    end

    if (options.driver or 'cache') == 'cache' and options.cache == nil then
        if not app:has(services.CACHE) then
            fail(NO_STORE)
        end

        options.cache = app:get(services.CACHE)
    end

    -- Функция зовётся после умолчания: вернувшая пусто — ошибка
    -- объявления, и отказывает она словом `tnt-session`, а не уводит
    -- сессии в кэш приложения молча.
    if type(options.cache) == 'function' then
        options.cache = options.cache(app)
    end

    return options
end

--- Кладёт менеджер сессий в контейнер, если сессии есть.
---
--- Собирается при применении, как кэш: настройки проверяются сразу,
--- и опечатка видна оператору в alerts, а не первым запросом.
---@param app TntDiContainer
---@param config table Разделы настроек
---@param declared TntFrameworkSessionSpec|false|nil Объявление `session`
function Module.declare(app, config, declared)
    local section = config.session

    if declared == false or (declared == nil and section == nil) then
        return
    end

    demand(explain.options(section or {}, 'приложение: раздел session', SECTION))

    app:value(Module.NAME, session.new(options_of(app, declared or {}, section or {})))
end

--- Своё объявление приложения — копией: таблица либо то, что отдала
--- функция от контейнера; без объявления — пустая таблица.
---
--- Копия — потому что объявление живёт дольше одного применения,
--- и дописанное в него здесь досталось бы следующему. Не таблица
--- уходит вторым значением как есть: её вид реестр `tnt-middleware`
--- проверяет своим текстом.
---@param own any Поле `layers` либо `groups` объявления
---@param app TntDiContainer
---@return table|nil copy
---@return any odd То, что не таблица
local function own_of(own, app)
    local declared = own

    if type(own) == 'function' then
        declared = own(app)
    end

    if declared == nil then
        return {}
    end

    if type(declared) ~= 'table' then
        return nil, declared
    end

    return over(declared, {})
end

--- Слои реестра: свои слои приложения и слой `session` — фабрика
--- менеджера из контейнера.
---
--- Менеджер берётся при сборке роутера, после провайдеров и `build`:
--- подменённый ими через `app:replace`, он и встанет в слой. Свои слои
--- приходят и функцией от контейнера, а контейнера до применения нет,
--- поэтому имя `session` проверяется здесь, при сборке.
---@param app TntDiContainer
---@param own table<string, function>|(fun(app: TntDiContainer): table)|nil Поле `layers` объявления
---@return any
function Module.layers(app, own)
    local layers, odd = own_of(own, app)

    if layers == nil then
        return odd
    end

    if layers[Module.NAME] ~= nil then
        fail(OWN_SESSION)
    end

    if app:has(Module.NAME) then
        layers[Module.NAME] = app:get(Module.NAME):factory()
    end

    return layers
end

--- Группы реестра: свои группы приложения и группа `web` — слой сессий,
--- если они есть, а за ним записи группы `web` приложения.
---
--- Без сессий и без своей группы `web` она пустая. Группа `web`
--- приложения не списком уходит реестру как есть: его отказ назовёт её.
---@param app TntDiContainer
---@param own table<string, any[]>|(fun(app: TntDiContainer): table)|nil Поле `groups` объявления
---@return any
function Module.groups(app, own)
    local groups, odd = own_of(own, app)

    if groups == nil then
        return odd
    end

    local listed = groups[Module.WEB]

    if listed ~= nil and type(listed) ~= 'table' then
        return groups
    end

    local web = app:has(Module.NAME) and { Module.NAME } or {}

    for _, entry in ipairs(listed or {}) do
        -- Запись бывает именем и списком `{ имя, параметры }`.
        if (type(entry) == 'table' and entry[1] or entry) == Module.NAME then
            fail(WEB_SESSION)
        end

        table.insert(web, entry)
    end

    groups[Module.WEB] = web

    return groups
end

--- Общие данные страниц от сессий: токен формы, если сессии есть.
---
--- Сессия берётся из запроса полем, под которым её кладёт слой, а имя
--- поля данных — у директивы `@csrf` (`template.csrf.DATA`): разойдись
--- они, форма перестала бы проходить. Таблица каждый раз новая: поверх
--- неё фреймворк кладёт данные приложения, и общая на все запросы
--- унесла бы токен одного посетителя в страницу другому.
---@param app TntDiContainer
---@return TntRouterViewData|nil
function Module.view_data(app)
    if not app:has(Module.NAME) then
        return nil
    end

    return function(request)
        local current = request[session.layer.FIELD]

        if current == nil then
            return {}
        end

        return { [template.csrf.DATA] = current:token() }
    end
end

return Module
