--- Переводы приложения: каталог `lang/`, файл на язык.
---
---     lang/ru.lua   return { home = { title = 'Главная' } }
---     lang/en.lua   return { home = { title = 'Home' } }
---
--- Файл — данные Lua, а не модуль: его читает `tnt-config` без глобалов
--- и без байт-кода, так что строка перевода кода не исполняет, а файл,
--- который вместо строк что-то делает, — отказ сборки. Имя файла — метка
--- языка по форме: `ru.lua`, `en-GB.lua`.
---
--- Язык по умолчанию — настройка `app.locale` (файл `config/app.lua`).
--- При одном файле язык по умолчанию — он сам; при нескольких без
--- настройки сборка отказывает: выбрать язык за приложение по алфавиту
--- значило бы однажды заговорить с посетителем по-английски только
--- потому, что кто-то добавил `de.lua`.
---
--- Каталог перечитывается на каждом применении конфигурации, как и
--- страницы: правка перевода подхватывается `config:reload()`.
---
--- Слово отказа тоже берётся из переводов — строкой раздела `errors`:
---
---     lang/en.lua   return { errors = { ['404'] = 'No such address',
---                                       order = { gone = 'Order {id} is gone' } } }
---
--- Связь делает раскладка, а не пакеты: каталог отказов ядра получает
--- функцию перевода (`refusals`), и ни пакет отказов, ни пакет переводов
--- друг о друге не знают.

local config = require('tnt.config')
local errors = require('tnt.error')
local i18n = require('tnt.i18n')

local files = require('tnt.framework.files')

--- Отказ без места вызова: текст уходит оператору в alerts.
local fail = require('tnt.must.fail').raise

local Module = {}

--- Раздел строк со словами отказов.
Module.ERRORS = 'errors'

--- Переводчик по каталогу и разделу `app` настроек.
---
--- Пусто — переводов нет: каталога нет, он выключен (`lang = false`)
--- либо в нём нет ни одного файла.
---@param directory string|false|nil Каталог переводов
---@param section any Раздел `app` настроек
---@return TntI18n|nil
function Module.of(directory, section)
    if not directory then
        return nil
    end

    local messages = {}
    local tags = {}

    for _, file in ipairs(files.of(directory, 'переводов')) do
        local tree, err = config.read(file.path)

        if tree == nil then
            fail(('приложение: переводы: %s'):format(tostring(err)))
        end

        messages[file.name] = tree
        table.insert(tags, file.name)
    end

    if tags[1] == nil then
        return nil
    end

    local default = type(section) == 'table' and section.locale or nil

    if default == nil and tags[2] ~= nil then
        fail(
            ('приложение: переводы: в %s языков несколько (%s) — '):format(
                directory,
                table.concat(tags, ', ')
            )
                .. 'назовите язык по умолчанию настройкой app.locale'
        )
    end

    local options = { locale = default or tags[1], messages = messages }
    local complaint = i18n.explain(options)

    if complaint ~= nil then
        fail('приложение: переводы: ' .. complaint)
    end

    return i18n.new(options)
end

--- Ключ строки со словом отказа.
---
--- Отказ со своим кодом ищется по коду: `errors.order.gone`. Чужой отказ
--- без кода — «нет такого адреса» роутера — сказан по статусу, и ключ
--- у него по статусу: `errors.404`. Отказ с кодом по статусу не ищется:
--- общая строка о статусе сказала бы о нём меньше, чем его собственное
--- слово, — и сказала бы это даже на языке по умолчанию.
---@param err TntError
---@return string
local function key_of(err)
    if err.code == errors.REFUSED then
        return ('%s.%d'):format(Module.ERRORS, err.status)
    end

    return Module.ERRORS .. '.' .. err.code
end

--- Язык запроса: из самого запроса, если слой языка его туда положил,
--- иначе из контекста.
---
--- Запрос — первым: отказ парой проходит слой насквозь, и рисуют его
--- уже снаружи, где контекста с языком нет, а в запросе язык остался.
---@param lang TntI18n
---@param request any
---@return string
local function spoken(lang, request)
    local asked = type(request) == 'table' and i18n.normalize(request[i18n.REQUEST_KEY]) or nil

    return asked or lang:locale()
end

--- Подстановки слова отказа: его собственные и опознаватель происшествия.
---
--- Опознаватель — отдельно: у внутренней поломки он весь её ответ,
--- а среди подстановок его нет — каталог кладёт его в слово сам.
---@param err TntError
---@return table
local function substitutions(err)
    local params = { incident = err.incident }

    for name, value in pairs(err.params) do
        params[name] = value
    end

    return params
end

--- Перевод слова отказа для каталога отказов ядра.
---
--- Строки нет ни в языке запроса, ни в языке по умолчанию — перевода нет,
--- и уходит слово самого отказа: ключ вместо слова, как у страницы,
--- здесь ушёл бы клиенту в теле. Строка языка по умолчанию, напротив,
--- годится: её написало приложение, и она главнее слова пакета.
---
--- Переводчик берётся на каждом отказе, а не при заведении: сборка
--- вправе подменить его своим (`app:replace`).
---@param current fun(): TntI18n
---@return TntErrorTranslate
function Module.refusals(current)
    return function(err, request)
        local lang = current()
        local key = key_of(err)
        local tag = spoken(lang, request)

        if not lang:has(key, tag) and not lang:has(key, lang.default) then
            return nil
        end

        return lang:get(key, substitutions(err), tag), tag
    end
end

--- Заводит директивы страниц: `@lang('home.title')` — строка по ключу,
--- `@choice('nodes', count)` — форма при числе, `@locale()` — язык запроса.
---
--- Переводчик берётся на каждом вызове, а не при заведении: сборка
--- приложения вправе подменить его своим (`app:replace`) — например,
--- с правилом множественного числа для языка, которого среди встроенных
--- нет, — и страницы должны говорить подменённым.
---@param view TntTemplateEngine
---@param current fun(): TntI18n
function Module.directives(view, current)
    view:directive('lang', function(key, params)
        return current():get(key, params)
    end)

    view:directive('choice', function(key, count, params)
        return current():choice(key, count, params)
    end)

    view:directive('locale', function()
        return current():locale()
    end)
end

return Module
