--- Срез шага из каталога миграций на 300 000 строк под секундой ядра.
---
--- Шаг образца переписывает каждую строку одной транзакцией: на 3.8 это
--- около трёх секунд работы без уступки. Без среза ядро рвёт его
--- на секунде «fiber slice is exceeded», и отказ подсказывает, как задать
--- срез в каталоге; со срезом 30 из файла `database/migrations` шаг
--- проходит.
---
--- **В `make test` пропускается.** Стоит она около пяти секунд, а
--- мутационный прогон гоняет набор пакета на каждого мутанта. Сам способ
--- поломки гейт видит и так — в `migrations_slice_test.lua` тот же срыв
--- ловится на срезе в 20 мс и полутора тысячах строк. Здесь — настоящий
--- объём, и гоняет его отдельная цель:
---
---     make test-large

local t = require('luatest')

local helper = dofile('test/helper.lua')
local testing = helper.testing

local g = t.group('tnt.framework.migrations_large')

--- Срез ядра по умолчанию, секунды: под ним и живёт файбер шага.
local SLICE = 1

--- Строк в probe.
local ROWS = 300000

--- Арена узла: триста тысяч строк и их новые версии в одной транзакции
--- в умолчания оснастки не влезают.
local MEMORY = 256 * 1024 * 1024

local enabled = helper.large_tests()

g.before_all(function()
    if enabled then
        g.server = helper.start_node(MEMORY)
    end
end)

g.after_all(function()
    if g.server ~= nil then
        testing.stop_node(g.server)
    end
end)

g.test_three_hundred_thousand_rows_need_the_slice_from_the_file = function()
    t.skip_if(not enabled, 'долгая проверка: включается TNT_LARGE_TESTS=1 (make test-large)')

    local failed = helper.raised_under_slice(g.server, helper.path('migrations_unsliced'), ROWS, SLICE)

    t.assert_equals(failed, {
        err = 'шаг 1 не применён: шаг шёл без уступки дольше среза файбера (fiber slice is exceeded); '
            .. 'долгому шагу задают срез в секундах: register(1, step, { slice = секунды }), '
            .. 'а в migrations ядра и в файле database/migrations — { step = шаг, slice = секунды } вместо шага',
        version = 0,
        first = 'old',
        last = 'old',
    })

    local passed = helper.raised_under_slice(g.server, helper.path('migrations_sliced'), ROWS, SLICE)

    t.assert_equals(passed, { applied = { 1 }, version = 1, first = 'new', last = 'new' })
end
