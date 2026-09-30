--- Каталог настроек `config/`: файл на раздел, функция от окружения.
---
--- Каждый файл возвращает функцию от окружения и отвечает таблицей,
--- результат лежит в `config.<имя файла>`; окружение ядро перечитывает на
--- каждом применении. Имена, занятые ядром (`role`, `instance`, …),
--- отвергаются при загрузке.

local config_file = require('tnt.config')
local kernel = require('tnt.kernel')

local files = require('tnt.framework.files')

--- Отказ без места вызова: текст уходит оператору в alerts.
local fail = require('tnt.must.fail').raise

local Module = {}

--- Список — множеством: по нему спрашивают «есть ли имя».
---@param list string[]
---@return table<string, boolean>
local function set_of(list)
    local members = {}

    for _, item in ipairs(list) do
        members[item] = true
    end

    return members
end

--- Имена разделов, занятые ядром.
local reserved = set_of(kernel.RESERVED)

---@class TntFrameworkConfigFile
---@field name string Имя файла без расширения — имя раздела
---@field builder fun(env: TntEnv): table Сборщик раздела от окружения

--- Файлы каталога настроек, загруженные и проверенные.
---
--- Читаются при загрузке модуля роли: файл, не вернувший функцию, —
--- ошибка программиста, и обнаружиться она обязана до первого
--- применения. Модуль ищется по имени: каталог лежит на `package.path`,
--- как и всё приложение.
---@param directory string
---@param inside string|nil Имя модуля каталога — у раскладки внутри пакета
---@return TntFrameworkConfigFile[]
function Module.files(directory, inside)
    local loaded = {}

    for _, file in ipairs(files.of(directory, 'настроек', inside)) do
        if reserved[file.name] then
            fail(('приложение: имя настроек %s занято ядром'):format(file.name))
        end

        local builder = require(file.module)

        if type(builder) ~= 'function' then
            fail(
                ('приложение: модуль настроек %s должен вернуть функцию от окружения'):format(
                    file.module
                )
            )
        end

        table.insert(loaded, { name = file.name, builder = builder })
    end

    return loaded
end

--- Разделы настроек из окружения по файлам каталога — для ядра.
---
--- Отказ сборщика называет файл; текст `tnt.env` тайн не несёт.
---@param loaded TntFrameworkConfigFile[]
---@return fun(env: TntEnv): table<string, table>
function Module.sections_of(loaded)
    return function(env)
        local sections = {}

        for _, file in ipairs(loaded) do
            local ok, value = pcall(file.builder, env)

            if not ok then
                fail(('%s: %s'):format(file.name, tostring(value)))
            end

            if type(value) ~= 'table' then
                fail(
                    ('%s должен вернуть таблицу, получено %s'):format(
                        file.name,
                        type(value)
                    )
                )
            end

            sections[file.name] = value
        end

        return sections
    end
end

--- Разделы из собранного заранее файла: окружение не читается.
---
--- Файл проверяется при загрузке роли — испорченный собранный файл
--- должен упасть здесь, а не на применении; разделы отдаются копией
--- на каждое применение, чтобы приложение не правило общую таблицу.
---
--- Читает `tnt.config`: файл — данные, а не код, и пустой либо оборванный
--- файл — отказ, а не приложение без единой настройки.
---@param path string
---@return fun(env: TntEnv): table<string, table>
function Module.cached(path)
    -- Под `pcall`: путь с чужим расширением — ошибка объявления, и отказ
    -- о ней идёт оператору без места, как все отказы объявления.
    local ok, sections, err = pcall(config_file.read, path)

    if not ok then
        fail(('приложение: %s'):format(sections))
    end

    if sections == nil then
        fail(
            ('приложение: собранные настройки не прочитаны: %s'):format(
                tostring(err)
            )
        )
    end

    return function()
        return table.deepcopy(sections)
    end
end

return Module
