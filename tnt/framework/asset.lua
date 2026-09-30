--- Пути к собранным файлам: помощник `asset` и директива `@asset`.
---
--- Сборщик (Vite, esbuild, любой другой) ставит в имя файла отпечаток
--- содержимого — `app-BX7Yy2Qk.css` — и пишет соответствие в манифест
--- `public/build/manifest.json`:
---
---     { "resources/css/app.scss": { "file": "assets/app-BX7Yy2Qk.css" } }
---
--- Страница при этом пишет исходное имя, а браузеру уходит имя
--- с отпечатком, которому можно дать год кэша:
---
---     <link rel="stylesheet" href="@asset('resources/css/app.scss')">
---
--- Отпечаток нужен ровно для этого: файл под таким именем больше
--- не меняется, меняется имя, — и раздача вправе сказать браузеру
--- «больше не спрашивай» (документ `tnt-router`, «Раздача файлов»).
---
--- Манифест читается один раз и живёт в памяти: на боевом узле он
--- меняется вместе с выкладкой, то есть с перезапуском процесса.
--- В разработке (`watch`) он перечитывается по времени правки — сборка
--- идёт на каждую правку стилей, и перезапускать ради неё узел незачем.
---
--- **Отказа тут не бывает.** Нет манифеста, нет записи, испорченный
--- JSON — путь уходит как есть, а в журнал ложится предупреждение,
--- и ровно одно на причину: страница, которая рисуется десять раз
--- в секунду, иначе залила бы журнал. Уронить страницу из-за непрошедшей
--- сборки нельзя: без стилей она некрасива, без страницы — недоступна.

local fio = require('fio')
local json = require('json')

local log = require('tnt.log').new('tnt.framework')

local Module = {}

--- Как зовётся манифест внутри каталога сборки.
Module.MANIFEST = 'manifest.json'

--- Каталог сборки внутри `public`: так его зовут сборщики по умолчанию.
Module.BUILD = 'build'

---@class TntFrameworkAssetsOptions
---@field path string Каталог `public` от корня раскладки
---@field build string|nil Каталог сборки внутри него; по умолчанию build
---@field watch boolean|nil Перечитывать манифест по времени правки

--- Пишет предупреждение один раз на причину.
---@param state table
---@param key string Причина: имя файла или путь манифеста
---@param message string
---@param fields table|nil Подробности записи
local function warn_once(state, key, message, fields)
    if state.warned[key] then
        return
    end

    state.warned[key] = true

    log.warn(message, fields)
end

--- Читает манифест сборки.
---
--- Пустая таблица вместо отказа: страница с исходными путями рисуется
--- и без сборки — в разработке её открывают раньше, чем соберут стили.
---@param state table
---@return table<string, table>
local function read(state)
    local handle = fio.open(state.manifest, { 'O_RDONLY' })

    if handle == nil then
        warn_once(
            state,
            state.manifest,
            ('приложение: манифеста сборки %s нет — пути уходят как есть'):format(
                state.manifest
            )
        )

        return {}
    end

    local text = handle:read()

    handle:close()

    local ok, decoded = pcall(json.decode, text)

    if not ok or type(decoded) ~= 'table' then
        -- Причина — полем, а не в тексте: отказ разбора несёт кусок
        -- самого файла, а кусок с обрезанной кириллицей — уже не UTF-8,
        -- и журнал выбросил бы такое сообщение целиком.
        warn_once(
            state,
            state.manifest,
            ('приложение: манифест сборки %s не разобран — пути уходят как есть'):format(
                state.manifest
            ),
            { reason = tostring(decoded) }
        )

        return {}
    end

    return decoded
end

--- Записи манифеста: прочитанные однажды либо перечитанные по правке.
---@param state table
---@return table<string, table>
local function entries_of(state)
    if state.entries ~= nil and not state.watch then
        return state.entries
    end

    if state.watch then
        local stat = fio.stat(state.manifest)

        if stat ~= nil and state.entries ~= nil and stat.mtime == state.mtime then
            return state.entries
        end

        -- Манифеста нет — сборка ещё не прошла: в следующий раз смотрим
        -- снова, а не запоминаем пустоту до перезапуска узла.
        state.mtime = stat ~= nil and stat.mtime or nil
    end

    state.entries = read(state)

    return state.entries
end

--- Адрес от корня сайта: ведущая черта ставится, если её нет.
---
--- Путь из манифеста и путь, отданный как есть, обязаны выглядеть
--- одинаково: относительный адрес в странице читается от её каталога,
--- и на `/customers/7` тот же `resources/css/app.scss` превратился бы
--- в `/customers/resources/css/app.scss`.
---@param name string
---@return string
local function rooted(name)
    -- Ведущая черта ищется образцом, а не срезом: у среза `sub(1, 1)`
    -- мутант `sub(0, 1)` в Lua значит то же самое, и строка выглядела бы
    -- проверенной, не будучи ею.
    if name:find('^/') ~= nil then
        return name
    end

    return '/' .. name
end

--- Заводит помощника: имя из страницы — адрес для браузера.
---@param options TntFrameworkAssetsOptions
---@return fun(name: string): string
function Module.new(options)
    local build = options.build or Module.BUILD

    local state = {
        manifest = fio.pathjoin(options.path, build, Module.MANIFEST),
        prefix = '/' .. build,
        watch = options.watch == true,
        warned = {},
    }

    return function(name)
        local entry = entries_of(state)[name]

        if type(entry) ~= 'table' or type(entry.file) ~= 'string' then
            warn_once(
                state,
                name,
                ('приложение: в манифесте сборки нет «%s» — путь уходит как есть'):format(
                    name
                )
            )

            return rooted(name)
        end

        return state.prefix .. '/' .. entry.file
    end
end

--- Помощник по объявлению и разделу `app.assets`.
---
--- Раздел настроек главнее объявления: каталог сборки с перечитыванием
--- задаются из окружения, а не правкой кода. Без каталога `public`
--- помощника нет вовсе: подставлять пути некуда, и молчаливый `asset`,
--- отдающий что попало, хуже его отсутствия.
---@param declared string|TntFrameworkAssetsOptions|false|nil Что объявлено либо взято по соглашению
---@param section any Раздел `app` настроек
---@return (fun(name: string): string)|nil
function Module.of(declared, section)
    if declared == false then
        return nil
    end

    ---@type any
    local options = type(declared) == 'table' and declared or { path = declared }
    local path, build, watch = options.path, options.build, options.watch

    ---@type any
    local assets = type(section) == 'table' and section.assets or nil

    if type(assets) == 'table' then
        build = assets.build or build

        -- Признак сверяется с пустотой, а не берётся «или»: `watch = false`
        -- в разделе обязан выключать перечитывание, а не пропадать.
        if assets.watch ~= nil then
            watch = assets.watch
        end
    end

    if path == nil then
        return nil
    end

    return Module.new({ path = path, build = build, watch = watch })
end

return Module
