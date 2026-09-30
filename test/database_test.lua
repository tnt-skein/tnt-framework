--- Проверки наполнения и состояния схемы у роли и генератора файла
--- миграции: `role.seed`, `role.migrations`, `framework.migrations`.
---
--- Узел не поднимается: роль применяется на двойниках мира ядра,
--- а состояние схемы подменяется у `tnt.schema` — его сведение версии
--- и журнала проверяет сам пакет на настоящем узле.

local t = require('luatest')
local fio = require('fio')
local json = require('json')

local helper = dofile('test/helper.lua')
local testing = helper.testing

local g = t.group('tnt.framework.database')

---@type any
local framework

---@type string
local directory

--- Каталог миграций образца: 001_customers и 002_orders.
local MIGRATIONS = helper.path('migrations')

g.before_each(function()
    framework = helper.load(helper.world())
    directory = fio.tempdir()
end)

g.after_each(function()
    fio.rmtree(directory)
    rawset(_G, 'seeded_with', nil)
    helper.forget_globals()
    helper.unload()
end)

--- Кладёт файл в каталог проверки.
---@param name string Имя файла
---@param text string
local function write(name, text)
    local file = fio.open(fio.pathjoin(directory, name), { 'O_WRONLY', 'O_CREAT', 'O_TRUNC' }, 420)

    file:write(text)
    file:close()
end

--- Роль с каталогом наполнителей проверки: боевой и разработки.
---@return any role
local function seeded_role()
    write('statuses.lua', "return function(app) rawset(_G, 'seeded_with', app:has('config')) return 2 end")
    write('demo.lua', "return { dev = true, after = { 'statuses' }, run = function() end }")

    return framework.new(helper.spec({ seeders = directory }))
end

-- ─── Наполнение ─────────────────────────────────────────────────────────────

g.test_seed_runs_the_directory_with_the_container_of_the_applied_role = function()
    local role = seeded_role()

    local report, err = role.seed()

    t.assert_equals(report, nil)
    t.assert_equals(
        err,
        'приложение test.app на этом узле не применено: наполнять нечем'
    )

    role.apply(nil)

    t.assert_equals(role.seed(), { seeded = { { name = 'statuses', count = 2 } }, skipped = { 'demo' } })
    t.assert_equals(
        rawget(_G, 'seeded_with'),
        true,
        'наполнитель получил контейнер применения'
    )
    t.assert_equals(
        role.seed({ dev = true, only = { 'demo' } }),
        { seeded = { { name = 'statuses', count = 2 }, { name = 'demo' } }, skipped = {} }
    )

    -- Каталог читается на каждом вызове: правка видна без перезапуска.
    write('statuses.lua', 'return function() return 5 end')

    t.assert_equals(role.seed().seeded, { { name = 'statuses', count = 5 } })
end

g.test_seed_answers_text_to_a_human_and_json_to_a_program = function()
    local role = seeded_role()

    role.apply(nil)

    t.assert_equals(
        role.seed({ format = 'text' }),
        table.concat({
            'наполнитель  записей',
            '-----------  -------',
            'statuses     2',
            'пропущены наполнители разработки: demo',
            '',
        }, '\n')
    )
    t.assert_equals(
        role.seed({ format = 'text', dev = true }),
        table.concat({
            'наполнитель  записей',
            '-----------  -------',
            'statuses     2',
            'demo',
            '',
        }, '\n')
    )

    local answer = role.seed({ format = 'json' })

    t.assert_equals(json.decode(answer), { seeded = { { name = 'statuses', count = 2 } }, skipped = { 'demo' } })
    t.assert_str_contains(role.seed({ format = 'json', dev = true }), '"skipped":[]')
end

-- Среда production отвергает наполнители разработки: среду называет
-- окружение приложения (`TNT_ENV`).
g.test_seed_refuses_development_data_in_production = function()
    local env = testing.module('tnt.env')

    env._set_source({
        getenv = function(name)
            return name == env.ENV_NAME and 'production' or nil
        end,
    })

    local role = seeded_role()

    role.apply(nil)

    local report, err = role.seed({ dev = true })

    env._set_source(nil)

    t.assert_equals(report, nil)
    t.assert_equals(
        err,
        'наполнители разработки в среде production не запускаются'
    )
end

g.test_seed_without_a_directory_or_with_nothing_to_seed = function()
    local role = framework.new(helper.spec())

    role.apply(nil)

    t.assert_equals(
        { role.seed() },
        { nil, 'у приложения test.app нет каталога наполнителей database/seeders' }
    )

    local empty = framework.new(helper.spec({ seeders = directory }))

    empty.apply(nil)

    t.assert_equals(empty.seed({ format = 'text' }), 'наполнять нечего\n')
    t.assert_equals({ empty.seed({ only = { 'users' } }) }, { nil, 'наполнителя users нет' })
end

-- Негодные настройки вызова — ошибка в коде, который зовёт метод:
-- бросок со строкой вызывающего.
g.test_wrong_options_of_a_call_are_thrown_at_the_caller = function()
    local role = seeded_role()

    t.assert_error_msg_matches(
        '.*database_test.lua:%d+: настройки наполнения: ключа «fromat» нет, есть dev, format, only',
        function()
            role.seed({ fromat = 'text' })
        end
    )
    t.assert_error_msg_matches(
        '.*database_test.lua:%d+: настройки состояния схемы.format — одно из «text», «json», а не «yaml»',
        function()
            role.migrations({ format = 'yaml' })
        end
    )
end

-- ─── Состояние схемы ────────────────────────────────────────────────────────

--- Состояние, которое отдаст подменённый `tnt.schema`.
---@return table
local function status()
    return {
        instance = 'storage-001-a',
        current = 1,
        target = 3,
        steps = {
            {
                version = 1,
                applied = true,
                registered = true,
                applied_at = 1790000000.75,
                instance = 'storage-001-b',
                elapsed_ms = 3.26,
            },
            { version = 2, applied = false, registered = true },
            { version = 3, applied = false, registered = false },
        },
    }
end

g.test_migrations_names_the_files_of_the_steps = function()
    testing.module('tnt.schema').status = status

    local role = framework.new(helper.spec({ migrations = MIGRATIONS }))
    local found = role.migrations()

    t.assert_equals(found.steps[1].file, '001_customers')
    t.assert_equals(found.steps[2].file, '002_orders')
    t.assert_equals(found.steps[3].file, nil)
    t.assert_equals(found.current, 1)

    -- Без каталога миграций имён файлов нет, а шаги — есть.
    local bare = framework.new(helper.spec()).migrations()

    t.assert_equals(bare.steps[1].file, nil)
    t.assert_equals(#bare.steps, 3)
end

g.test_migrations_answers_text_to_a_human_and_json_to_a_program = function()
    testing.module('tnt.schema').status = status

    local role = framework.new(helper.spec({ migrations = MIGRATIONS }))

    t.assert_equals(
        role.migrations({ format = 'text' }),
        table.concat({
            'узел storage-001-a: версия в базе 1, в коде 3',
            'шаг  файл           состояние   применён (UTC)       узел           мс',
            '---  -------------  ----------  -------------------  -------------  ---',
            '1    001_customers  применён    2026-09-21 14:13:20  storage-001-b  3.3',
            '2    002_orders     ждёт',
            '3                   нет в коде',
            '',
        }, '\n')
    )

    local decoded = json.decode(role.migrations({ format = 'json' }))

    t.assert_equals(decoded.instance, 'storage-001-a')
    t.assert_equals(decoded.steps[1].file, '001_customers')
    t.assert_equals(decoded.steps[1].applied_at, 1790000000.75)
    t.assert_equals(decoded.steps[3], { version = 3, applied = false, registered = false })
end

g.test_migrations_names_every_state_of_a_step = function()
    testing.module('tnt.schema').status = function()
        return {
            instance = 'router-001-a',
            current = 2,
            target = 1,
            steps = {
                { version = 1, applied = true, registered = true },
                { version = 2, applied = true, registered = false },
            },
        }
    end

    t.assert_equals(
        framework.new(helper.spec()).migrations({ format = 'text' }),
        table.concat({
            'узел router-001-a: версия в базе 2, в коде 1',
            'шаг  файл  состояние             применён (UTC)  узел  мс',
            '---  ----  --------------------  --------------  ----  --',
            '1          применён',
            '2          применён, нет в коде',
            '',
        }, '\n')
    )
end

-- Один шаг — тоже таблица: шапка рисуется, как только есть хоть одна строка.
g.test_migrations_of_a_single_step_is_a_table = function()
    testing.module('tnt.schema').status = function()
        return {
            instance = 'storage-001-a',
            current = 0,
            target = 1,
            steps = { { version = 1, applied = false, registered = true } },
        }
    end

    t.assert_equals(
        framework.new(helper.spec()).migrations({ format = 'text' }),
        table.concat({
            'узел storage-001-a: версия в базе 0, в коде 1',
            'шаг  файл  состояние  применён (UTC)  узел  мс',
            '---  ----  ---------  --------------  ----  --',
            '1          ждёт',
            '',
        }, '\n')
    )
end

g.test_migrations_of_an_empty_schema_and_a_refusal = function()
    local schema = testing.module('tnt.schema')

    schema.status = function()
        return { instance = 'storage-001-a', current = 0, target = 0, steps = {} }
    end

    local role = framework.new(helper.spec())

    t.assert_equals(
        role.migrations({ format = 'text' }),
        'узел storage-001-a: версия в базе 0, в коде 0\n'
    )
    t.assert_str_contains(role.migrations({ format = 'json' }), '"steps":[]')

    schema.status = function()
        return nil, 'состояние схемы не прочитать: box не инициализирован'
    end

    t.assert_equals(
        { role.migrations() },
        { nil, 'состояние схемы не прочитать: box не инициализирован' }
    )
end

-- ─── Файл миграции ──────────────────────────────────────────────────────────

--- Генератор файла проверяется из каталога проверки как из рабочего.
---
--- Каталог по умолчанию отсчитывается от рабочего каталога: генератор,
--- сломанный так, что берёт его вместо названного, завёл бы файлы в дереве
--- проверок, и раскладка по соглашению у следующих проверок нашла бы там
--- чужие шаги. Заведённое в каталоге проверки уходит вместе с ним.
local creating = t.group('tnt.framework.migrations.create')

--- Рабочий каталог до проверки: в него возвращаются после неё.
---@type string
local here

creating.before_each(function()
    framework = helper.load(helper.world())
    directory = fio.tempdir()
    here = fio.cwd()
    fio.chdir(directory)
end)

creating.after_each(function()
    fio.chdir(here)
    fio.rmtree(directory)
    helper.forget_globals()
    helper.unload()
end)

creating.test_create_lays_the_next_number_and_the_header = function()
    local catalog = testing.module('tnt.framework.migrations')
    local path = directory .. '/001_orders.lua'

    -- Права сверяются без маски процесса: под обычной маской 022 права
    -- по умолчанию у fio.open — те же 0644, и проверка их не различила бы.
    local mask = fio.umask(0)
    local created = { pcall(catalog.create, 'orders', directory) }

    fio.umask(mask)

    t.assert_equals(created, { true, path })
    -- 420 — это 0644: файл правит владелец, остальные только читают;
    -- остаток от 512 (01000) — права без рода файла.
    t.assert_equals(fio.stat(path).mode % 512, 420)
    t.assert_equals(
        fio.open(path):read(),
        table.concat({
            '--- Версия 1: orders.',
            '---',
            '--- Шаг миграции tnt-schema: номер версии — приставка имени файла. Шаг',
            '--- выполняется один раз, в одной транзакции с записью версии, поэтому',
            '--- if_not_exists ему не нужен. Отката нет: следующая правка схемы —',
            '--- следующий файл, совместимый с кодом этой версии, — а шаг обязан',
            '--- читаться кодом прежней версии: узлы обновляются по одному.',
            '---@param box table',
            'return function(box)',
            'end',
            '',
        }, '\n')
    )

    -- Номер — наибольший в каталоге плюс один, а не число файлов.
    write('009_statuses.lua', 'return function() end')

    local next_path = catalog.create('add_status_to_orders', directory)

    t.assert_equals(next_path, directory .. '/010_add_status_to_orders.lua')
    t.assert_str_contains(fio.open(next_path):read(), '--- Версия 10: add status to orders.\n')

    -- Заведённый файл — годный шаг: каталог читается, имена видны.
    t.assert_equals(type(framework.migrations(directory)[1]), 'function')
    t.assert_equals(
        catalog.names(directory),
        { [1] = '001_orders', [9] = '009_statuses', [10] = '010_add_status_to_orders' }
    )
end

creating.test_create_takes_a_one_letter_name_and_digits_after_the_first_letter = function()
    local catalog = testing.module('tnt.framework.migrations')

    -- Букву правило требует только первой: дальше годны и цифры,
    -- а имя может быть одной буквой.
    t.assert_equals(catalog.create('a', directory), directory .. '/001_a.lua')
    t.assert_equals(catalog.create('v2_orders1', directory), directory .. '/002_v2_orders1.lua')
end

creating.test_create_makes_the_directory_and_takes_the_default_one = function()
    local catalog = testing.module('tnt.framework.migrations')
    local nested = directory .. '/app/database/migrations'

    t.assert_equals(catalog.create('customers', nested), nested .. '/001_customers.lua')

    -- Без каталога — каталог по соглашению от рабочего, то есть от каталога
    -- проверки.
    t.assert_equals(catalog.create('users'), 'database/migrations/001_users.lua')
    t.assert_equals(fio.path.is_file(directory .. '/database/migrations/001_users.lua'), true)
end

creating.test_create_refuses_a_bad_name_and_a_place_it_cannot_write = function()
    local catalog = testing.module('tnt.framework.migrations')

    for _, name in ipairs({ 'Orders', '1orders', 'add-status', 'a.b', '' }) do
        t.assert_error_msg_equals(
            ('имя миграции — строчные латинские буквы, цифры и «_», с буквы, а не «%s»'):format(
                name
            ),
            catalog.create,
            name,
            directory
        )
    end

    t.assert_error_msg_equals(
        'имя миграции — строчные латинские буквы, цифры и «_», с буквы, а не «nil»',
        catalog.create,
        nil,
        directory
    )
    t.assert_error_msg_equals(
        'каталог миграций /dev/null/migrations не заведён',
        catalog.create,
        'orders',
        '/dev/null/migrations'
    )

    -- Файл без номера в каталоге — каталог испорчен, и номер не посчитать.
    write('orders.lua', 'return function() end')

    t.assert_error_msg_equals(
        ('приложение: миграция %s/orders.lua должна начинаться с номера версии: 001_имя.lua'):format(
            directory
        ),
        catalog.create,
        'users',
        directory
    )

    fio.unlink(directory .. '/orders.lua')
    -- 365 и 493 — это 0555 и 0755: каталог только для чтения и снова свой.
    fio.chmod(directory, 365)

    local ok, err = pcall(catalog.create, 'users', directory)

    fio.chmod(directory, 493)

    t.assert_equals(ok, false)
    t.assert_str_contains(
        tostring(err),
        ('файл миграции %s/001_users.lua не заведён: '):format(directory)
    )
    t.assert_str_contains(tostring(err), 'Permission denied')
end
