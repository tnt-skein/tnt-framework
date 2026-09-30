--- Режим обслуживания по объявлению и разделу `app.maintenance`.

local downtime = require('tnt.downtime')

--- Отказ без места вызова: текст уходит оператору в alerts.
local fail = require('tnt.must.fail').raise

local Module = {}

--- Переключатель режима обслуживания по объявлению и разделу `app`.
---
--- Раздел `app.maintenance` настроек — `driver`, `path`, `except` — главнее
--- объявления, а драйвер пока один, файл: иной названный — опечатка, и она
--- обязана обнаружиться сборкой, а не тем, что режим молча не включился.
---@param declared string|TntDowntimeOptions|false|nil Что объявлено либо взято по соглашению
---@param section any Раздел `app` настроек
---@return TntDowntime|nil
function Module.of(declared, section)
    if declared == false then
        return nil
    end

    ---@type any
    local options = type(declared) == 'table' and declared or { path = declared }
    local path, except = options.path, options.except

    ---@type any
    local maintenance = type(section) == 'table' and section.maintenance or nil

    if type(maintenance) == 'table' then
        if maintenance.driver ~= nil and maintenance.driver ~= 'file' then
            fail(
                ('приложение: режим обслуживания: драйвер %s не поддерживается, есть только file'):format(
                    tostring(maintenance.driver)
                )
            )
        end

        path = maintenance.path or path
        except = maintenance.except or except
    end

    if path == nil then
        return nil
    end

    return downtime.new({ path = path, except = except })
end

return Module
