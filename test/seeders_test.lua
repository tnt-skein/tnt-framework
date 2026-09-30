--- Проверки наполнителей: договор файла, порядок по зависимостям, запуск,
--- наполнители разработки и отказы.
---
--- Каталоги собираются на время проверки: у каждой ошибки каталога свой
--- набор файлов, и держать их образцами в дереве значило бы завести
--- десяток каталогов ради строки в каждом.

local t = require('luatest')
local fio = require('fio')

local helper = dofile('test/helper.lua')

local g = t.group('tnt.framework.seeders')

---@type any
local seeders

---@type string
local directory

g.before_each(function()
    helper.load(helper.world())
    seeders = require('tnt.framework.seeders')
    directory = fio.tempdir()
end)

g.after_each(function()
    fio.rmtree(directory)
    helper.forget_globals()
    helper.unload()
end)

--- Кладёт файлы наполнителей в каталог проверки.
---@param sources table<string, string> Имя файла без `.lua` → текст
local function write(sources)
    for name, text in pairs(sources) do
        local file = fio.open(fio.pathjoin(directory, name .. '.lua'), { 'O_WRONLY', 'O_CREAT', 'O_TRUNC' }, 420)

        file:write(text)
        file:close()
    end
end

--- Имена наполнителей по порядку запуска.
---@param list TntFrameworkSeeder[]
---@return string[]
local function names_of(list)
    local names = {}

    for _, seeder in ipairs(list) do
        table.insert(names, seeder.name)
    end

    return names
end

--- Наполнитель для запуска без файла.
---@param name string
---@param run function
---@param opts { after: string[]|nil, dev: boolean|nil }|nil
---@return TntFrameworkSeeder
local function seeder(name, run, opts)
    opts = opts or {}

    return { name = name, run = run, after = opts.after or {}, dev = opts.dev == true }
end

-- ─── Каталог ────────────────────────────────────────────────────────────────

g.test_a_file_returns_a_function_or_a_table_and_the_name_is_the_file_name = function()
    write({
        statuses = 'return function(app) return app.count end',
        customers = "return { after = { 'statuses' }, dev = false, run = function() end }",
        demo = "return { dev = true, run = function() end, after = { 'customers' } }",
    })

    local found = seeders.of(directory)

    t.assert_equals(names_of(found), { 'statuses', 'customers', 'demo' })
    t.assert_equals(found[1].after, {})
    t.assert_equals(found[1].dev, false)
    t.assert_equals(found[1].run({ count = 7 }), 7)
    t.assert_equals(found[2].after, { 'statuses' })
    t.assert_equals(found[2].dev, false)
    t.assert_equals(found[3].dev, true)
end

-- Зависимость раньше того, кто её ждёт; общая зависимость двоих
-- наполняет один раз, а независимые идут по имени.
g.test_the_order_follows_dependencies_then_names = function()
    write({
        b = "return { after = { 'd' }, run = function() end }",
        a = 'return function() end',
        c = "return { after = { 'd', 'a' }, run = function() end }",
        d = 'return function() end',
    })

    t.assert_equals(names_of(seeders.of(directory)), { 'a', 'd', 'b', 'c' })
end

g.test_a_file_of_the_wrong_kind_is_refused_with_its_path = function()
    write({ plain = 'return 42' })

    t.assert_error_msg_equals(
        ('приложение: наполнитель %s/plain.lua должен вернуть '):format(directory)
            .. 'функцию от контейнера либо таблицу { run, after, dev }',
        seeders.of,
        directory
    )
end

g.test_a_table_with_a_stray_key_or_a_wrong_field_is_refused = function()
    write({ typo = 'return { runn = function() end }' })

    t.assert_error_msg_equals(
        ('приложение: наполнитель %s/typo.lua: ключа «runn» нет, есть after, dev, run'):format(
            directory
        ),
        seeders.of,
        directory
    )

    fio.unlink(fio.pathjoin(directory, 'typo.lua'))
    write({ flag = "return { run = function() end, dev = 'yes' }" })

    t.assert_error_msg_equals(
        ('приложение: наполнитель %s/flag.lua.dev — логическое значение, а не строка'):format(
            directory
        ),
        seeders.of,
        directory
    )
end

g.test_a_missing_dependency_is_refused = function()
    write({ customers = "return { after = { 'statuses' }, run = function() end }" })

    t.assert_error_msg_equals(
        ('приложение: наполнитель customers ждёт statuses, а такого в %s нет'):format(
            directory
        ),
        seeders.of,
        directory
    )
end

-- Круг называется цепочкой ожидания: кто кого ждёт и где круг замкнулся.
-- Первым идёт наполнитель, чья зависимость уже наполнена, — в цепочке
-- её нет.
g.test_a_circle_of_dependencies_is_refused_with_the_chain = function()
    write({
        a_root = "return { after = { 'b_leaf', 'c' }, run = function() end }",
        b_leaf = 'return function() end',
        c = "return { after = { 'd' }, run = function() end }",
        d = "return { after = { 'c' }, run = function() end }",
    })

    t.assert_error_msg_equals(
        'приложение: наполнители ждут друг друга по кругу: a_root → c → d → c',
        seeders.of,
        directory
    )
end

-- Боевой наполнитель не вправе ждать наполнителя разработки: в бою его
-- зависимость не наполнится. Наполнитель разработки ждать его вправе.
g.test_a_production_seeder_may_not_wait_for_a_development_one = function()
    write({
        demo = 'return { dev = true, run = function() end }',
        more = "return { dev = true, after = { 'demo' }, run = function() end }",
    })

    t.assert_equals(names_of(seeders.of(directory)), { 'demo', 'more' })

    write({ customers = "return { after = { 'demo' }, run = function() end }" })

    t.assert_error_msg_equals(
        'приложение: наполнитель customers идёт и в production, а ждёт demo — наполнитель разработки',
        seeders.of,
        directory
    )
end

g.test_a_directory_that_is_not_there_is_refused = function()
    t.assert_error_msg_equals(
        'приложение: каталог наполнителей /нет/такого не прочитан',
        seeders.of,
        '/нет/такого'
    )
end

-- ─── Запуск ─────────────────────────────────────────────────────────────────

g.test_seeders_run_in_order_with_the_container_and_report_counts = function()
    local calls = {}
    local app = { name = 'контейнер' }

    local report, err = seeders.run({
        seeder('statuses', function(given)
            table.insert(calls, { 'statuses', given.name })

            return 2
        end),
        seeder('customers', function()
            table.insert(calls, { 'customers' })
        end),
        seeder('empty', function()
            return 0
        end),
        seeder('odd', function()
            return 'не число'
        end),
    }, app)

    t.assert_equals(err, nil)
    t.assert_equals(calls, { { 'statuses', 'контейнер' }, { 'customers' } })
    t.assert_equals(report, {
        seeded = {
            { name = 'statuses', count = 2 },
            { name = 'customers' },
            { name = 'empty', count = 0 },
            { name = 'odd' },
        },
        skipped = {},
    })
end

-- Наполнители разработки идут, только когда их попросили, а в среде
-- production — не идут и тогда.
g.test_development_seeders_run_only_when_asked_and_never_in_production = function()
    local ran = {}

    local list = {
        seeder('statuses', function()
            table.insert(ran, 'statuses')
        end),
        seeder('demo', function()
            table.insert(ran, 'demo')
        end, { dev = true }),
    }

    t.assert_equals(seeders.run(list, {}), { seeded = { { name = 'statuses' } }, skipped = { 'demo' } })
    t.assert_equals(seeders.run(list, {}, { environment = 'production' }).skipped, { 'demo' })
    t.assert_equals(
        seeders.run(list, {}, { dev = true, environment = 'staging' }),
        { seeded = { { name = 'statuses' }, { name = 'demo' } }, skipped = {} }
    )
    t.assert_equals(ran, { 'statuses', 'statuses', 'statuses', 'demo' })

    local report, err = seeders.run(list, {}, { dev = true, environment = 'production' })

    t.assert_equals(report, nil)
    t.assert_equals(
        err,
        'наполнители разработки в среде production не запускаются'
    )
    t.assert_equals(#ran, 4, 'в production не пошёл ни один')
end

-- Названные идут вместе с теми, кого они ждут, — и только они.
g.test_only_the_named_run_with_their_dependencies = function()
    local ran = {}

    local function recorded(name)
        return function()
            table.insert(ran, name)
        end
    end

    local list = {
        seeder('statuses', recorded('statuses')),
        seeder('regions', recorded('regions')),
        seeder('customers', recorded('customers'), { after = { 'statuses' } }),
        seeder('orders', recorded('orders'), { after = { 'customers' } }),
        seeder('demo', recorded('demo'), { dev = true }),
    }

    local report = seeders.run(list, {}, { only = { 'orders', 'demo' } })

    t.assert_equals(ran, { 'statuses', 'customers', 'orders' })
    t.assert_equals(
        report.skipped,
        { 'demo' },
        'названный наполнитель разработки без dev виден пропущенным'
    )

    local missing, err = seeders.run(list, {}, { only = { 'orderz' } })

    t.assert_equals(missing, nil)
    t.assert_equals(err, 'наполнителя orderz нет')
end

-- Отказ и бросок останавливают запуск и называют, кто успел до него.
g.test_a_refusal_or_a_throw_stops_the_run_and_names_what_was_done = function()
    local ran = {}

    local function recorded(name)
        return function()
            table.insert(ran, name)
        end
    end

    local report, err = seeders.run({
        seeder('statuses', recorded('statuses')),
        seeder('customers', recorded('customers')),
        seeder('orders', function()
            return nil, 'нет связи с хранилищем'
        end),
        seeder('users', recorded('users')),
    }, {})

    t.assert_equals(report, nil)
    t.assert_equals(
        err,
        'наполнитель orders не выполнен: нет связи с хранилищем; до него наполнили: statuses, customers'
    )
    t.assert_equals(ran, { 'statuses', 'customers' })

    report, err = seeders.run({
        seeder('orders', function()
            return false, 'дубликат'
        end),
    }, {})

    t.assert_equals(
        err,
        'наполнитель orders не выполнен: дубликат; до него наполнили: никого'
    )
    t.assert_equals(report, nil)

    report, err = seeders.run({
        seeder('orders', function()
            error({ code = 7 })
        end),
    }, {})

    t.assert_str_matches(
        err,
        'наполнитель orders не выполнен: table: 0x%x+; до него наполнили: никого'
    )
    t.assert_equals(report, nil)

    report, err = seeders.run({
        seeder('orders', function()
            error('сломался', 0)
        end),
    }, {})

    t.assert_equals(
        err,
        'наполнитель orders не выполнен: сломался; до него наполнили: никого'
    )
    t.assert_equals(report, nil)
end

-- До отказа успел ровно один — он и назван.
g.test_a_refusal_after_one_seeder_names_that_one = function()
    local report, err = seeders.run({
        seeder('statuses', function() end),
        seeder('orders', function()
            return nil, 'нет связи'
        end),
    }, {})

    t.assert_equals(report, nil)
    t.assert_equals(
        err,
        'наполнитель orders не выполнен: нет связи; до него наполнили: statuses'
    )
end

g.test_an_empty_list_seeds_nothing = function()
    t.assert_equals(seeders.run({}, {}, nil), { seeded = {}, skipped = {} })
end
