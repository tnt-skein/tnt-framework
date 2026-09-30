--- Провайдеры: список имён модулей либо каталог, проверенные при загрузке.
---
--- Это части `build`, `ready`, `routes` и `iproto` приложения, разложенные
--- по файлам; права пакету лезть в контейнер они не дают — провайдер пишет
--- само приложение.

local files = require('tnt.framework.files')

--- Отказ без места вызова: текст уходит оператору в alerts.
local fail = require('tnt.must.fail').raise

local Module = {}

---@class TntFrameworkProvider
---@field name string Имя модуля целиком — им провайдер зовётся в журнале
---@field register (fun(app: TntDiContainer, config: TntKernelConfig))|nil Объявления контейнера
---@field ready TntKernelReady|nil Действие по box.status
---@field routes TntKernelRoutes|nil Маршруты HTTP провайдера
---@field iproto TntKernelIproto|nil Функции iproto провайдера

--- Какие действия бывают у провайдера: объявления, готовность и свои
--- маршруты с функциями iproto.
---@type table<string, boolean>
local PROVIDER_ACTIONS = { register = true, ready = true, routes = true, iproto = true }

--- Провайдер, проверенный при загрузке роли.
---
--- Каждый — таблица с `register`, `ready`, `routes` и/или `iproto`; иное
--- поле — опечатка, и она обязана обнаружиться при загрузке, а не
--- на первом применении.
---@param name string Имя модуля
---@param value any Что модуль вернул
---@return TntFrameworkProvider
local function checked_provider(name, value)
    if type(value) ~= 'table' then
        fail(
            ('приложение: провайдер %s должен вернуть таблицу с register и ready'):format(
                name
            )
        )
    end

    for key, action in pairs(value) do
        if not PROVIDER_ACTIONS[key] then
            fail(
                ('приложение: провайдер %s: нет такого действия — %s'):format(
                    name,
                    tostring(key)
                )
            )
        end

        if type(action) ~= 'function' then
            fail(
                ('приложение: провайдер %s: %s должно быть функцией'):format(
                    name,
                    key
                )
            )
        end
    end

    if next(value) == nil then
        fail(('приложение: провайдер %s ничего не делает'):format(name))
    end

    return { name = name, register = value.register, ready = value.ready, routes = value.routes, iproto = value.iproto }
end

--- Провайдеры по списку имён модулей либо по каталогу.
---
--- Список (`bootstrap/providers.lua`) — порядок задаёт он сам.
--- Каталог — порядок по имени файла. Имя провайдера в журнале — имя
--- модуля целиком: у списка оно и есть единственное имя, а два файла
--- с одним именем в разных каталогах в нём различимы.
---@param declared string|any[]
---@param inside string|nil Имя модуля каталога — у раскладки внутри пакета
---@return TntFrameworkProvider[]
function Module.of(declared, inside)
    local names = {}

    if type(declared) == 'string' then
        for _, file in ipairs(files.of(declared, 'провайдеров', inside)) do
            table.insert(names, file.module)
        end
    else
        for index, name in ipairs(declared) do
            if type(name) ~= 'string' then
                fail(
                    ('приложение: providers: запись №%d должна быть именем модуля'):format(
                        index
                    )
                )
            end

            table.insert(names, name)
        end
    end

    local loaded = {}

    for _, name in ipairs(names) do
        table.insert(loaded, checked_provider(name, require(name)))
    end

    return loaded
end

return Module
