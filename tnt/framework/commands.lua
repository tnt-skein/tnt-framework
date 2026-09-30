--- Команды узла у роли приложения: `db:seed` и `migrate:status`
--- функцией iproto `<имя>_command`.
---
--- Наполнителю нужен контейнер применения со службами, состоянию схемы —
--- спейсы узла, поэтому эти команды выполняет узел. Консоль узла им
--- не годится: ответ она заворачивает в YAML, а отказ и бросок кончаются
--- кодом 0 — сценарий не отличит удачу от отказа, а JSON придёт строкой
--- внутри YAML. Роль публикует функцию, которая выполняет командную
--- строку на `tnt-console` и отдаёт итог таблицей `{ code, stdout,
--- stderr }`; сценарий оператора зовёт её через `console.remote`
--- и кончается тем кодом, которым команда кончилась на узле.
---
--- Учётке оператора хватает права на одну функцию — ни `eval` для всего,
--- ни прав на спейсы ей не нужно:
---
---     credentials:
---       users:
---         operator:
---           password: '{{ context.operator_password }}'
---           privileges:
---             - permissions: [execute]
---               lua_call: [app_command]
---
--- Команда идёт от имени `admin` (`box.session.su`): право на функцию
--- и есть право на команды. Функцию по `lua_call` узел исполняет с правами
--- вызывающего, а наполнитель пишет в спейсы приложения — права на каждый
--- пришлось бы выдавать оператору поимённо и держать в согласии с кодом
--- наполнителей, и выданные они давали бы писать туда и мимо команд.
--- Команд две, обе — код приложения, и командная строка другого
--- не выполнит: незнакомое имя — неверный вызов.
---
--- Функция публикуется на каждом узле приложения — ядро снимает её
--- вместе с прочими функциями iproto на `stop`. Без права её не позвать,
--- а учётке с правом на `eval` она ничего не добавляет.

local console = require('tnt.console')
local external = require('tnt.external')

local database = require('tnt.framework.database')

---@class TntFrameworkCommands
---@field _set_source fun(replacement: table|nil) Подмена смены учётки — для проверок; ставит её `external.install`
local Module = {}

--- Имя сценария оператора: в строке вызова и в справке команд.
Module.SCRIPT = 'console.lua'

--- Учётка, от имени которой идут команды.
Module.USER = 'admin'

--- Внешняя зависимость: смена учётки на время команды. Через неё затем,
--- что в процессе проверок `box` не поднят, а `su` без него бросает.
local source = external.install(Module, {
    su = function(user, body)
        return box.session.su(user, body)
    end,
})

--- Имя функции iproto, которая выполняет команды приложения.
---
--- Имя приложения — имя его журнала: в нём бывают точка и дефис
--- (`acme.board`), а `lua_call` читает точку как путь по таблицам.
--- Поэтому они становятся «_»: у приложения `app` функция — `app_command`,
--- у приложения `acme.board` — `acme_board_command`.
---@param name string Имя приложения
---@return string
function Module.function_name(name)
    return (name:gsub('[%.%-]', '_')) .. '_command'
end

--- Команды роли: приложение командной строки `tnt-console`.
---@param role TntFrameworkRole Роль с методами `seed` и `migrations`
---@param name string Имя приложения — в справке команд
---@return TntConsoleApp
function Module.of(role, name)
    local app = console.new({
        name = Module.SCRIPT,
        description = ('Команды приложения %s на узле'):format(name),
    })

    database.commands(app, role)

    return app
end

--- Модуль iproto роли: функция, которая выполняет командную строку.
---
--- Роль заводит ядро из объявления, в котором этот модуль уже стоит,
--- поэтому роль приходит функцией: модуль iproto зовётся на применении,
--- когда роль давно есть. Команды собираются заново на каждое
--- применение, как и всё, что ядро собирает на нём.
---@param name string Имя приложения
---@param role_of fun(): TntFrameworkRole Роль приложения
---@return TntKernelIproto
function Module.iproto(name, role_of)
    local published = Module.function_name(name)

    return function()
        local commands = Module.of(role_of(), name)

        return {
            [published] = function(argv)
                return source().su(Module.USER, function()
                    return commands:reply(argv)
                end)
            end,
        }
    end
end

return Module
