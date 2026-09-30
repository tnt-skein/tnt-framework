--- Срез шага из каталога миграций — на настоящем узле.
---
--- Двойники остальных проверок показывают, что таблица со срезом дошла
--- до реестра, но не то, что срез шагу достался: это видно только там,
--- где ядро Tarantool само рвёт работу без уступки «fiber slice is
--- exceeded». Срез вызывающего — 20 мс, строк — полторы тысячи: шаг
--- образца съедает срез работой без уступки и потом обращается к box
--- тысячи раз, а ядро сверяет срез раз в тысячу обращений. Настоящий
--- объём — 300 000 строк под секундой ядра — в `migrations_large_test.lua`.

local t = require('luatest')

local helper = dofile('test/helper.lua')
local testing = helper.testing

local g = t.group('tnt.framework.migrations_slice')

--- Срез вызывающего, секунды: короче работы без уступки в шаге образца.
local SLICE = 0.02

--- Строк в probe: больше тысячи обращений к box.
local ROWS = 1500

g.before_all(function()
    g.server = helper.start_node(32 * 1024 * 1024)
end)

g.after_all(function()
    testing.stop_node(g.server)
end)

g.test_a_step_with_a_slice_from_the_directory_outlives_the_callers_slice = function()
    local result = helper.raised_under_slice(g.server, helper.path('migrations_sliced'), ROWS, SLICE)

    t.assert_equals(result, { applied = { 1 }, version = 1, first = 'new', last = 'new' })
end

g.test_the_same_step_without_a_slice_fails_with_a_hint_for_the_directory = function()
    local result = helper.raised_under_slice(g.server, helper.path('migrations_unsliced'), ROWS, SLICE)

    t.assert_equals(result, {
        err = 'шаг 1 не применён: шаг шёл без уступки дольше среза файбера (fiber slice is exceeded); '
            .. 'долгому шагу задают срез в секундах: register(1, step, { slice = секунды }), '
            .. 'а в migrations ядра и в файле database/migrations — { step = шаг, slice = секунды } вместо шага',
        version = 0,
        first = 'old',
        last = 'old',
    })
end
