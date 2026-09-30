--- Кэш и сессии на спейсах на свежем узле: пустая база, первое применение.
---
--- Спейсы заводят шаги миграции, а миграции ядро поднимает событием
--- `box.status` — после применения роли и только у собранного приложения.
--- Кэш приложения собирается при применении, хранилище сессий — при
--- загрузке роли. Ищи они спейс сразу — первое применение на пустой базе
--- отказало бы, и шаги, которые завели бы спейсы, не пошли бы никогда.
--- Показать этот круг может только настоящее ядро Tarantool: двойник
--- мира зовёт применение и событие сам.

local t = require('luatest')

local helper = dofile('test/helper.lua')
local testing = helper.testing

local g = t.group('tnt.framework.space_cache_live')

--- Роль образца — модуль от каталога пакета: узел ищет модули и от него,
--- раньше поставленных копий.
local ROLE = 'test.app_with_space_cache.bootstrap.app'

--- Спейсы шагов образца: кэш, сессии и спейсы их тегов.
local SPACES = { 'app_cache', 'app_cache_tags', 'app_sessions', 'app_sessions_tags' }

g.before_all(function()
    g.server = helper.start_configured('space-001-a', { 'roles: [' .. ROLE .. ']' })
end)

g.after_all(function()
    testing.stop_node(g.server)
end)

--- Что узел знает о приложении: предупреждения ядра, собрано ли оно
--- и какие спейсы шагов есть.
---@return { alerts: string[], applied: boolean, spaces: string[] }
local function observed()
    return g.server:exec(function(role_name, names)
        local messages, spaces = {}, {}

        for _, alert in ipairs(require('config'):info().alerts) do
            table.insert(messages, alert.message)
        end

        for _, name in ipairs(names) do
            if box.space[name] ~= nil then
                table.insert(spaces, name)
            end
        end

        return { alerts = messages, applied = require(role_name).status().applied, spaces = spaces }
    end, { ROLE, SPACES })
end

g.test_the_first_apply_on_an_empty_base_passes_and_the_migrations_follow = function()
    ---@type { alerts: string[], applied: boolean, spaces: string[] }
    local state

    -- Шаги схемы идут событием ядра в своём файбере: подъём узла кончается
    -- раньше них.
    t.helpers.retrying({ timeout = 10 }, function()
        state = observed()

        t.assert_equals(state.spaces, SPACES)
    end)

    t.assert_equals(state.alerts, {}, 'первое применение прошло без отказа')
    t.assert_equals(state.applied, true)

    local report = g.server:exec(function(role_name)
        local app = require(role_name).container()
        local cache = app:get('cache')
        local sessions = app:get('session')

        cache:put('greeting', 'привет', 60)
        cache:tags('docs'):put('docs:7', 'страница', 60)

        local session = sessions:start(nil)

        session:put('visits', 1)

        local header = sessions:commit(session)
        local restored = sessions:start(header:match('^(tnt_session=[^;]+)'))

        return {
            greeting = cache:get('greeting'),
            stored = box.space.app_cache:get('demo:greeting') ~= nil,
            forgotten = cache:tags('docs'):flush(),
            visits = restored:get('visits'),
            sessions = box.space.app_sessions:count(),
        }
    end, { ROLE })

    t.assert_equals(report, {
        greeting = 'привет',
        stored = true,
        forgotten = 1,
        visits = 1,
        sessions = 1,
    })
end
