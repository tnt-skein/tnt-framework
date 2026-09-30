--- Файлы каталога раскладки и имена модулей по путям.
---
--- Каталоги настроек, провайдеров и миграций читаются одинаково:
--- файлы `*.lua` по порядку имён, потому что порядок имени и есть
--- порядок применения.

local fio = require('fio')

--- Отказ без места вызова: текст уходит оператору в alerts.
local fail = require('tnt.must.fail').raise

local Module = {}

--- Файлы `*.lua` каталога по порядку имён.
---
--- Порядок — по имени файла: он и есть порядок применения, и задаётся
--- приставкой в имени.
---
--- Имя модуля — путь с точками вместо косых черт, а у раскладки внутри
--- пакета — её приставка и имя каталога: путь установленного рока именем
--- модуля не будет, и без приставки `config/board.lua` пакета искался бы
--- по имени вида `.Users.…rocks.share.tarantool.acme.board.config.board`.
---@param directory string
---@param what string Что лежит в каталоге — для текста отказа
---@param inside string|nil Имя модуля самого каталога, например `acme.board.config`
---@return { name: string, path: string, module: string }[]
function Module.of(directory, what, inside)
    local names = fio.listdir(directory)

    if names == nil then
        fail(('приложение: каталог %s %s не прочитан'):format(what, directory))
    end

    table.sort(names)

    local prefix = inside or directory:gsub('/', '.')
    local files = {}

    for _, entry in ipairs(names) do
        local name = entry:match('^(.+)%.lua$')

        if name ~= nil then
            table.insert(files, { name = name, path = fio.pathjoin(directory, entry), module = prefix .. '.' .. name })
        end
    end

    return files
end

--- Имя модуля по пути от корня раскладки.
---
--- Корень `.` — это рабочий каталог узла, и приставки у модуля нет;
--- иной корень (`src`) входит в имя: `src.routes.web`.
---
--- У раскладки, которая лежит внутри пакета, путь от корня именем модуля
--- не будет: корень там — каталог установленного рока, и его путь
--- к загрузчику отношения не имеет. Такая раскладка называет своё имя
--- сама (`prefix`), и от корня берётся только хвост: `acme.board` плюс
--- `routes/api` — это `acme.board.routes.api`, где бы рок ни лежал.
---@param base string
---@param relative string Путь от корня без расширения
---@param prefix string|nil Имя модуля корня раскладки; пусто — имя из пути
---@return string
function Module.module_of(base, relative, prefix)
    if prefix ~= nil then
        return ('%s.%s'):format(prefix, (relative:gsub('/', '.')))
    end

    local path = base == '.' and relative or (base .. '/' .. relative)

    return (path:gsub('/', '.'))
end

return Module
