--- Проверки команд узла у роли приложения: функция iproto
--- `<имя>_command` и команды `db:seed` и `migrate:status` на ней.
---
--- Функцию публикует ядро на применении роли, и зовётся она здесь так,
--- как её зовёт iproto: глобалом с командной строкой. `box` в процессе
--- проверок не поднят, и смена учётки подменена записью; настоящая
--- смена проверяется на узле. Что итог доходит до сценария оператора
--- с тем же кодом, проверяют `tnt-console` (`console.remote`) и проверка
--- сценария образца.

local t = require('luatest')
local fio = require('fio')
local json = require('json')

local helper = dofile('test/helper.lua')
local testing = helper.testing

local g = t.group('tnt.framework.commands')

--- Функция команд приложения `test.app`.
local COMMAND = 'test_app_command'

---@type any
local framework

---@type string
local directory

--- От чьего имени шли команды.
---@type string[]
local users

g.before_each(function()
    framework = helper.load(helper.world())
    directory = fio.tempdir()
    users = {}

    testing.module('tnt.framework.commands')._set_source({
        su = function(user, fn, ...)
            table.insert(users, user)

            return fn(...)
        end,
    })
end)

g.after_each(function()
    helper.forget_globals()
    helper.unload()
    fio.rmtree(directory)
end)

--- Кладёт файл наполнителя в каталог проверки.
---@param name string Имя файла
---@param text string
local function write(name, text)
    testing.write_file(fio.pathjoin(directory, name), text)
end

--- Роль с каталогом наполнителей проверки, применённая: боевой
--- наполнитель и наполнитель разработки.
---@return any role
local function applied_role()
    write('statuses.lua', 'return function() return 2 end')
    write('demo.lua', "return { dev = true, after = { 'statuses' }, run = function() end }")

    local role = framework.new(helper.spec({ seeders = directory, migrations = helper.path('migrations') }))

    role.apply(nil)

    return role
end

--- Командная строка, выполненная функцией узла.
---@param argv string[]
---@return { code: integer, stdout: string, stderr: string }
local function command(argv)
    return rawget(_G, COMMAND)(argv)
end

-- ─── Имя функции ────────────────────────────────────────────────────────────

g.test_the_function_is_named_after_the_application = function()
    local commands = testing.module('tnt.framework.commands')

    t.assert_equals(commands.function_name('app'), 'app_command')
    -- Точку `lua_call` прочёл бы путём по таблицам, дефис — не имя.
    t.assert_equals(commands.function_name('tnt.admin'), 'tnt_admin_command')
    t.assert_equals(commands.function_name('shop-v2.web'), 'shop_v2_web_command')
    t.assert_equals(commands.SCRIPT, 'console.lua')
end

-- ─── Публикация ─────────────────────────────────────────────────────────────

g.test_the_role_publishes_the_function_on_apply_and_withdraws_it_on_stop = function()
    local role = framework.new(helper.spec())

    t.assert_equals(rawget(_G, COMMAND), nil)

    role.apply(nil)

    local help = command({ '--help' })

    t.assert_equals({ help.code, help.stderr }, { 0, '' })
    t.assert_equals(users, { 'admin' }, 'команда идёт от имени admin')
    t.assert_str_contains(
        help.stdout,
        'Вызов: console.lua [-h] <команда> ...\n\nКоманды приложения test.app на узле\n'
    )
    t.assert_str_contains(
        help.stdout,
        '   db:seed               Наполнить базу наполнителями database/seeders\n'
    )
    t.assert_str_contains(
        help.stdout,
        '   migrate:status        Какие шаги схемы применены на этом узле, когда и каким узлом\n'
    )

    role.stop()

    t.assert_equals(rawget(_G, COMMAND), nil)
end

g.test_the_name_of_the_function_is_taken_by_the_framework = function()
    local role = framework.new(helper.spec({
        iproto = function()
            return {
                [COMMAND] = function() end,
            }
        end,
    }))

    t.assert_error_msg_equals(
        'приложение test.app не собрано: iproto: функция test_app_command объявлена дважды',
        role.apply,
        nil
    )
end

-- ─── Наполнение ─────────────────────────────────────────────────────────────

g.test_db_seed_answers_a_human_and_a_program = function()
    applied_role()

    t.assert_equals(command({ 'db:seed' }), {
        code = 0,
        stdout = table.concat({
            'наполнитель  записей',
            '-----------  -------',
            'statuses     2',
            'пропущены наполнители разработки: demo',
            '',
        }, '\n'),
        stderr = '',
    })
    t.assert_equals(
        command({ 'db:seed', '--dev' }).stdout,
        'наполнитель  записей\n-----------  -------\nstatuses     2\ndemo\n'
    )

    local answer = command({ 'db:seed', '--json', '--dev', '--only', 'demo' })

    t.assert_equals({ answer.code, answer.stderr }, { 0, '' })
    t.assert_equals(answer.stdout:sub(-1), '\n', 'строка JSON кончается переводом строки')
    t.assert_str_contains(answer.stdout, '"skipped":[]')
    t.assert_equals(
        json.decode(answer.stdout),
        { seeded = { { name = 'statuses', count = 2 }, { name = 'demo' } }, skipped = {} }
    )

    -- Без ключа --only идут все: пустой список не значит «никого».
    t.assert_equals(json.decode(command({ 'db:seed', '--json' }).stdout).seeded, { { name = 'statuses', count = 2 } })
end

g.test_a_refusal_of_db_seed_ends_with_code_1_and_the_reason = function()
    applied_role()

    t.assert_equals(
        command({ 'db:seed', '--only', 'users' }),
        { code = 1, stdout = '', stderr = 'наполнителя users нет\n' }
    )

    write('statuses.lua', "return function() return nil, 'хранилище недоступно' end")

    t.assert_equals(command({ 'db:seed', '--dev' }), {
        code = 1,
        stdout = '',
        stderr = 'наполнитель statuses не выполнен: хранилище недоступно; до него наполнили: никого\n',
    })
end

g.test_db_seed_on_a_node_where_the_role_is_not_applied_refuses = function()
    local role = framework.new(helper.spec({ seeders = directory }))
    local commands = testing.module('tnt.framework.commands').of(role, 'test.app')

    t.assert_equals(commands:reply({ 'db:seed' }), {
        code = 1,
        stdout = '',
        stderr = 'приложение test.app на этом узле не применено: наполнять нечем\n',
    })
end

-- ─── Состояние схемы ────────────────────────────────────────────────────────

g.test_migrate_status_answers_a_human_and_a_program = function()
    testing.module('tnt.schema').status = function()
        return {
            instance = 'storage-001-a',
            current = 1,
            target = 2,
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
            },
        }
    end

    applied_role()

    t.assert_equals(command({ 'migrate:status' }), {
        code = 0,
        stdout = table.concat({
            'узел storage-001-a: версия в базе 1, в коде 2',
            'шаг  файл           состояние  применён (UTC)       узел           мс',
            '---  -------------  ---------  -------------------  -------------  ---',
            '1    001_customers  применён   2026-09-21 14:13:20  storage-001-b  3.3',
            '2    002_orders     ждёт',
            '',
        }, '\n'),
        stderr = '',
    })

    local answer = command({ 'migrate:status', '--json' })
    local decoded = json.decode(answer.stdout)

    t.assert_equals({ answer.code, answer.stderr }, { 0, '' })
    t.assert_equals(decoded.steps[2], { version = 2, file = '002_orders', applied = false, registered = true })
    t.assert_equals(decoded.current, 1)
end

g.test_migrate_status_keeps_an_empty_list_and_passes_a_refusal = function()
    local schema = testing.module('tnt.schema')

    schema.status = function()
        return { instance = 'router-001-a', current = 0, target = 0, steps = {} }
    end

    applied_role()

    -- Порядок ключей объекта JSON — порядок обхода таблицы: сверяются
    -- пустой список и перевод строки, а не текст целиком.
    local answer = command({ 'migrate:status', '--json' }).stdout

    t.assert_str_contains(answer, '"steps":[]')
    t.assert_equals(answer:sub(-1), '\n')
    t.assert_equals(json.decode(answer), { instance = 'router-001-a', current = 0, target = 0, steps = {} })

    schema.status = function()
        return nil, 'состояние схемы не прочитать: box не инициализирован'
    end

    t.assert_equals(command({ 'migrate:status' }), {
        code = 1,
        stdout = '',
        stderr = 'состояние схемы не прочитать: box не инициализирован\n',
    })
end

g.test_an_unknown_command_is_a_usage_error = function()
    applied_role()

    local answer = command({ 'db:sed' })

    t.assert_equals({ answer.code, answer.stdout }, { 2, '' })
    t.assert_str_contains(answer.stderr, 'Ошибка: команды «db:sed» нет\n')
end

-- ─── Учётка команды на узле ─────────────────────────────────────────────────

local on_node = t.group('tnt.framework.commands.on_node')

on_node.before_all(function()
    on_node.server = helper.start_node(64 * 1024 * 1024)
end)

on_node.after_all(function()
    testing.stop_node(on_node.server)
end)

-- Функцию по `lua_call` узел исполняет с правами вызывающего, а команда
-- идёт от имени admin: учётке оператора хватает права на функцию.
on_node.test_the_command_runs_as_admin_whoever_calls_it = function()
    local outcome = on_node.server:exec(function()
        ---@type any
        local commands = require('tnt.framework.commands')
        local seen = {}

        ---@type any
        local role = {
            seed = function()
                seen.user = box.session.effective_user()

                return { seeded = {}, skipped = {} }
            end,
        }

        local published = commands.iproto('probe', function()
            return role
        end)(nil)

        -- Зовёт гость, как оператор с правом только на функцию.
        local caller

        -- Аннотации знают `su` только с именем функции строкой.
        ---@type any
        local session = box.session

        local reply = session.su('guest', function()
            caller = box.session.effective_user()

            return published.probe_command({ 'db:seed', '--json' })
        end)

        return { reply = reply, user = seen.user, caller = caller }
    end)

    t.assert_equals(outcome, {
        reply = { code = 0, stdout = '{"seeded":[],"skipped":[]}\n', stderr = '' },
        user = 'admin',
        caller = 'guest',
    })
end
