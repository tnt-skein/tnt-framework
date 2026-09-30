--- Раскладка по соглашению от корня `base`.
---
--- Каталог на своём месте называть не нужно: приложение с обычной
--- раскладкой объявляется одним именем. Заполняются только поля, которых
--- в объявлении нет, и только если файл или каталог существует. Что
--- взято, записывается — чтобы умолчание не было молчаливым.

local fio = require('fio')

local files = require('tnt.framework.files')
local models_of = require('tnt.framework.models')

local Module = {}

--- Файлы `routes/`, которые не маршруты: слои и функции iproto.
local NOT_ROUTES = { middleware = true, iproto = true }

--- Каталог переведённых заранее страниц от корня приложения.
Module.VIEWS_COMPILED = 'bootstrap/cache/views'

--- Путь от корня раскладки: корень `.` — рабочий каталог узла,
--- и приставки у пути нет.
---@param base string
---@param relative string
---@return string
function Module.place(base, relative)
    return base == '.' and relative or (base .. '/' .. relative)
end

--- Раскладка по соглашению: что нашлось на своих местах.
---
--- Заполняются только поля, которых в объявлении нет, и только если
--- файл или каталог существует. Что взято, записывается — чтобы
--- умолчание не было молчаливым.
---@param spec TntFrameworkSpec
---@return table declared Поля объявления, дополненные соглашением
---@return table<string, string|string[]> layout Что и откуда взято
function Module.by_convention(spec)
    local base = spec.base or '.'
    local prefix = spec.prefix
    local declared = {}
    local layout = {}

    for key, value in pairs(spec) do
        declared[key] = value
    end

    declared.base = nil
    declared.prefix = nil

    local function place(relative)
        return Module.place(base, relative)
    end

    if declared.config == nil and fio.path.is_dir(place('config')) then
        declared.config = place('config')
        layout.config = declared.config
    end

    -- Собранные заранее настройки главнее каталога: пока файл на месте,
    -- окружение не читается вовсе.
    if declared.config_cache == nil and fio.path.is_file(place('bootstrap/cache/config.lua')) then
        declared.config_cache = place('bootstrap/cache/config.lua')
        layout.config_cache = declared.config_cache
    end

    if declared.migrations == nil and fio.path.is_dir(place('database/migrations')) then
        declared.migrations = place('database/migrations')
        layout.migrations = declared.migrations
    end

    if declared.seeders == nil and fio.path.is_dir(place('database/seeders')) then
        declared.seeders = place('database/seeders')
        layout.seeders = declared.seeders
    end

    -- Модели — только если они есть: пустой список ядру ни к чему,
    -- а в раскладке он выглядел бы как найденное.
    if declared.models == nil and fio.path.is_dir(place('app/models')) then
        local models, names = models_of.of(place('app/models'))

        if models[1] ~= nil then
            declared.models = models
            layout.models = names
        end
    end

    if declared.views == nil and fio.path.is_dir(place('resources/views')) then
        declared.views = place('resources/views')
        layout.views = declared.views
    end

    -- Переводы: файл на язык. Каталог — путь, а не модули: файлы читаются
    -- как данные (`tnt.framework.lang`).
    if declared.lang == nil and fio.path.is_dir(place('lang')) then
        declared.lang = place('lang')
        layout.lang = declared.lang
    end

    if declared.views_compiled == nil and fio.path.is_dir(place(Module.VIEWS_COMPILED)) then
        declared.views_compiled = place(Module.VIEWS_COMPILED)
        layout.views_compiled = declared.views_compiled
    end

    -- Каталог, который видит браузер: собранные стили и сценарии,
    -- картинки, шрифты. Отсюда же берётся манифест сборки для `asset`
    -- (`public/build/manifest.json`), а раздаёт файлы роутер —
    -- `route.serve('/build', 'public/build')`.
    if declared.public == nil and fio.path.is_dir(place('public')) then
        declared.public = place('public')
        layout.public = declared.public
    end

    if declared.downtime == nil and fio.path.is_dir(place('storage/framework')) then
        declared.downtime = place('storage/framework/down')
        layout.downtime = declared.downtime
    end

    if declared.providers == nil and fio.path.is_file(place('bootstrap/providers.lua')) then
        layout.providers = files.module_of(base, 'bootstrap/providers', prefix)
        declared.providers = require(layout.providers)
    end

    if fio.path.is_dir(place('routes')) then
        local routes = {}

        for _, file in ipairs(files.of(place('routes'), 'маршрутов')) do
            if not NOT_ROUTES[file.name] then
                table.insert(routes, files.module_of(base, 'routes/' .. file.name, prefix))
            end
        end

        if declared.routes == nil and routes[1] ~= nil then
            layout.routes = routes
            declared.routes = {}

            for _, module in ipairs(routes) do
                table.insert(declared.routes, require(module))
            end
        end

        for _, name in ipairs({ 'middleware', 'iproto' }) do
            if declared[name] == nil and fio.path.is_file(place('routes/' .. name .. '.lua')) then
                layout[name] = files.module_of(base, 'routes/' .. name, prefix)
                declared[name] = require(layout[name])
            end
        end
    end

    return declared, layout
end

return Module
