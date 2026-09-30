--- Каталог моделей `app/models/`: файл — модуль, возвращающий модель
--- `tnt.model`.
---
--- Модель — модуль приложения: его берут `require` службы и обработчики, а
--- ядру список нужен, чтобы привязать модели по месту узла при применении
--- конфигурации и опубликовать функции узла с данными по белому списку.
--- Порядок — по имени файла: привязке он безразличен, но список уходит в
--- `role.layout()` и в состояние роли, и там он обязан быть одним и тем же.
---
--- Шаг схемы модели каталог не регистрирует: он пишется файлом
--- `database/migrations/NNN_имя.lua` через `Model.migration()` — порядок
--- версий принадлежит приложению, а не алфавиту имён моделей.

local model = require('tnt.model')

local files = require('tnt.framework.files')

--- Отказ без места вызова: текст уходит оператору в alerts.
local fail = require('tnt.must.fail').raise

local Module = {}

--- Модель, проверенная при загрузке роли.
---
--- Файл, вернувший не модель, — ошибка с именем модуля: ядро отказало
--- бы номером записи, а номер в каталоге ни о чём не говорит.
---@param name string Имя модуля
---@param loaded any Что модуль вернул
---@return TntModel
local function checked_model(name, loaded)
    if not model.is(loaded) then
        fail(
            ('приложение: модель %s должна быть объявлена через model.define(…)'):format(
                name
            )
        )
    end

    return loaded
end

--- Модели каталога по порядку имён файлов.
---@param directory string Каталог моделей от корня раскладки
---@return TntModel[] models
---@return string[] names Имена модулей по порядку
function Module.of(directory)
    local models = {}
    local names = {}

    for _, file in ipairs(files.of(directory, 'моделей')) do
        table.insert(models, checked_model(file.module, require(file.module)))
        table.insert(names, file.module)
    end

    return models, names
end

return Module
