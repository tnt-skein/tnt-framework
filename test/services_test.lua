--- Проверки служб по разделам настроек: клиент Redis, драйвер базы,
--- кэш и ограничитель на общем клиенте, почта.
---
--- Сервер Redis — двойник на петле из помощника драйвера: по командам,
--- дошедшим до него, видно, чьим клиентом ходят кэш и ограничитель.
--- Рок драйвера базы подменяется у `tnt-storage`: соединений проверки
--- не открывают, а драйвер виден по отказу и по адресу клиента.

local t = require('luatest')

local helper = dofile('test/helper.lua')
local testing = helper.testing

local g = t.group('tnt.framework.services')

---@type TntKernelWorld
local world

---@type any
local framework

--- Объявление приложения с нужными полями поверх минимального.
local spec = helper.spec

--- Каталог настроек со службами: Redis, кэш, ограничитель, база.
local SERVICES = helper.path('config_services')

--- Переменные окружения, которыми проверки выбирают драйверы.
local VARIABLES = {
    'TEST_REDIS_PORT',
    'TEST_CACHE_DRIVER',
    'TEST_THROTTLE_DRIVER',
    'TEST_DATABASE_DRIVER',
    'TEST_MAIL_TLS',
    'TEST_FILES_ROOT',
}

g.before_each(function()
    world = helper.world()
    framework = helper.load(world)
end)

g.after_each(function()
    for _, name in ipairs(VARIABLES) do
        os.setenv(name, nil)
    end

    testing.module('tnt.storage.link')._set_source(nil)
    helper.forget_globals()
    helper.unload()
end)

--- Роль приложения с каталогом настроек, применённая.
---@param config string|nil Каталог настроек
---@param overrides table|nil Поля объявления сверх каталога
---@return any role
local function applied(config, overrides)
    local declared = { config = config }

    for key, value in pairs(overrides or {}) do
        declared[key] = value
    end

    local role = framework.new(spec(declared))

    role.apply(nil)

    return role
end

--- Запись о службе в состоянии контейнера.
---@param role any
---@param name string
---@return table|nil
local function entry(role, name)
    for _, item in ipairs(role.container():status().entries) do
        if item.name == name then
            return item
        end
    end

    return nil
end

-- ─── Redis: один клиент на кэш и ограничитель ───────────────────────────────

g.test_cache_and_throttle_on_redis_share_the_client_of_the_redis_section = function()
    local reply = helper.redis_reply
    -- Команды входа двойник отвечает сам: на них здесь пусто.
    local server = helper.redis_server(function(args)
        if args[1] == 'SET' then
            return reply.status('OK')
        end

        if args[1] == 'AUTH' or args[1] == 'SELECT' or args[1] == 'PING' then
            return nil
        end

        return reply.error('ERR сценарий не заведён')
    end)

    os.setenv('TEST_REDIS_PORT', tostring(server.port))
    os.setenv('TEST_CACHE_DRIVER', 'redis')
    os.setenv('TEST_THROTTLE_DRIVER', 'redis')

    local role = applied(SERVICES)
    local app = role.container()
    local client = app:get('redis')

    -- Клиента взяли кэш и ограничитель ещё при сборке: он собран один.
    t.assert_equals(entry(role, 'redis'), { name = 'redis', kind = 'single', built = true, replaced = false })
    t.assert_equals(client.where, '127.0.0.1:' .. server.port)
    t.assert_equals(app:get('cache'):status(), { name = 'redis', driver = 'redis', prefix = 'кэш:', ttl = nil })
    t.assert_equals(app:get('throttle').prefix, 'предел:')

    app:get('cache'):put('a', 1)

    local hits, err = app:get('throttle'):hit('вход', 60)

    t.assert_equals(hits, nil)
    t.assert_str_contains(tostring(err), 'сценарий не заведён')

    -- Обе команды пришли одному серверу по одному соединению: пул общий.
    local sent = {}

    -- Ключ у SET — второй, у EVAL — после сценария и числа ключей.
    for _, args in ipairs(server.commands) do
        if args[1] == 'SET' then
            table.insert(sent, 'SET ' .. args[2])
        elseif args[1] == 'EVAL' then
            table.insert(sent, 'EVAL ' .. args[4])
        end
    end

    t.assert_equals(sent, { 'SET cache:кэш:a', 'EVAL throttle:предел:вход' })
    t.assert_equals(server.connections, 1)

    -- Клиент закрывается вместе с контейнером.
    role.stop()

    t.assert_equals(client.closed, true)
    server.stop()
end

g.test_the_names_of_the_services_are_those_of_the_container = function()
    t.assert_equals(
        { framework.CACHE, framework.THROTTLE, framework.REDIS, framework.DB, framework.MAIL, framework.FILES },
        { 'cache', 'throttle', 'redis', 'db', 'mail', 'files' }
    )
end

g.test_the_redis_client_is_built_on_first_use_and_only_with_its_section = function()
    local role = applied(SERVICES)
    local app = role.container()

    -- Кэш и ограничитель в памяти клиента не берут: узел соединений
    -- не заводит, пока Redis не понадобится.
    t.assert_equals(entry(role, 'redis'), { name = 'redis', kind = 'single', built = false, replaced = false })
    t.assert_equals(app:get('redis').where, '127.0.0.1:6379')
    t.assert_equals(app:get('cache'):status().driver, 'memory')
    t.assert_equals(app:get('throttle'):hit('вход', 60), 1)

    t.assert_equals(applied(nil).container():has('redis'), false)
end

g.test_a_redis_driver_without_a_client_is_refused_by_the_assembly = function()
    t.assert_error_msg_equals(
        'приложение test.app не собрано: приложение: cache: драйверу redis нужен клиент — '
            .. 'раздел redis настроек либо cache.redis в объявлении',
        applied,
        nil,
        { cache = { driver = 'redis' } }
    )
    t.assert_error_msg_equals(
        'приложение test.app не собрано: приложение: throttle: драйверу redis нужен клиент — '
            .. 'раздел redis настроек либо throttle.redis в объявлении',
        applied,
        nil,
        { throttle = { driver = 'redis' } }
    )
end

-- ─── Ограничитель частоты ───────────────────────────────────────────────────

g.test_throttle_lives_in_the_container_and_the_section_beats_the_declaration = function()
    local limiter = applied(nil).container():get('throttle')

    t.assert_equals(limiter.prefix, '')
    t.assert_equals(limiter:hit('вход', 60), 1)
    t.assert_equals(limiter:hit('вход', 60), 2)

    -- Объявление задаёт умолчания, раздел настроек главнее.
    t.assert_equals(
        applied(nil, { throttle = { prefix = 'объявлено:' } }).container():get('throttle').prefix,
        'объявлено:'
    )
    t.assert_equals(
        applied(SERVICES, { throttle = { prefix = 'объявлено:' } }).container():get('throttle').prefix,
        'предел:'
    )

    t.assert_equals(applied(nil, { throttle = false }).container():has('throttle'), false)
    t.assert_error_msg_equals(
        'приложение: throttle должно быть table или false, получено number',
        framework.new,
        spec({ throttle = 7 })
    )
end

-- ─── База SQL ───────────────────────────────────────────────────────────────

g.test_the_database_section_names_the_driver_of_db = function()
    local link = testing.module('tnt.storage.link')

    link._set_source({
        require = function(name)
            return nil, 'нет рока ' .. name
        end,
    })

    -- Раздел без driver — настройки хранения самого Tarantool: базы нет.
    t.assert_equals(applied(SERVICES).container():has('db'), false)

    -- Драйвер собирается первым обращением: узел без рока применяется,
    -- а отказ — у того, кто позвал базу.
    for driver, rock in pairs({ postgres = 'pg', mysql = 'mysql' }) do
        os.setenv('TEST_DATABASE_DRIVER', driver)

        local role = applied(SERVICES)

        t.assert_equals(entry(role, 'db'), { name = 'db', kind = 'single', built = false, replaced = false })

        local ok, err = pcall(role.container().get, role.container(), 'db')

        t.assert_equals(ok, false)
        t.assert_str_contains(
            tostring(err),
            ('рок %s не установлен (нет рока %s)'):format(rock, rock)
        )
    end

    link._set_source({
        require = function()
            return {}
        end,
    })

    os.setenv('TEST_DATABASE_DRIVER', 'postgres')

    local role = applied(SERVICES)
    local db = role.container():get('db')

    t.assert_equals(db.where, 'db:5432/app')
    t.assert_equals(db.dialect.name, 'postgres')

    -- Драйвер закрывается вместе с контейнером.
    role.stop()

    t.assert_equals(db.closed, true)

    os.setenv('TEST_DATABASE_DRIVER', 'sqlite')

    t.assert_error_msg_equals(
        'приложение test.app не собрано: приложение: database.driver — одно из «mysql», «postgres», а не «sqlite»',
        applied,
        SERVICES
    )
end

-- ─── Почта ──────────────────────────────────────────────────────────────────

g.test_the_mail_section_configures_the_mail_of_the_process = function()
    t.assert_equals(applied(nil).container():has('mail'), false)

    local mail = applied(helper.path('config_mail')).container():get('mail')

    t.assert_is(mail, testing.module('tnt.mail'))
    t.assert_equals(mail.status().smtp.host, 'mail.example.org')
    t.assert_str_contains(
        mail.render({ to = 'a@example.org', subject = 'о', text = 'т' }),
        'From: noreply@example.org'
    )

    -- Негодный раздел — отказ применения, а не письмо, которое не уйдёт.
    os.setenv('TEST_MAIL_TLS', 'ssl')

    t.assert_error_msg_equals(
        'приложение test.app не собрано: неизвестный способ шифрования: ssl',
        applied,
        helper.path('config_mail')
    )
end

-- ─── Диски ──────────────────────────────────────────────────────────────────

g.test_the_files_section_builds_the_disks_and_the_client_of_the_bucket = function()
    local root = require('fio').tempdir()

    os.setenv('TEST_FILES_ROOT', root)

    local store = applied(SERVICES).container():get('files')
    local bucket = store:disk('s3')

    t.assert_is(store, applied(SERVICES).container():get('files') and store)
    t.assert_equals({ store.default, store:disk().driver, bucket.driver }, { 'local', 'local', 's3' })

    -- Локальный диск кладёт файл в каталог раздела.
    t.assert_equals({ store:disk():put('a/b.txt', 'данные') }, { true })
    t.assert_equals(testing.module('tnt.fs').read(root .. '/a/b.txt'), 'данные')
    t.assert_equals(store:disk():url('a/b.txt'), '/storage/a/b.txt')

    -- Клиент ведра собран из полей диска, а поля диска остались диску.
    t.assert_equals(bucket.backend.client.bucket, 'tnt-live')
    t.assert_equals(bucket.backend.client.settings.limits.timeout, 2)
    t.assert_equals(bucket.backend.prefix, 'uploads/')
    t.assert_equals(bucket:url('x.png'), 'https://cdn.example.org/x.png')

    require('fio').rmtree(root)
end

g.test_the_declaration_gives_what_a_section_cannot_carry = function()
    local signed = {}
    local client = testing.module('tnt.s3').new({
        endpoint = 'http://127.0.0.1:19000',
        bucket = 'own-bucket',
        access_key = 'ключ',
        secret_key = 'тайна',
    })
    local store = applied(SERVICES, {
            files = {
                disks = {
                    -- Подпись — функция: в раздел её не положить, а каталог
                    -- и адрес диска всё равно приходят разделом.
                    ['local'] = {
                        driver = 'local',
                        root = '/объявлено',
                        sign = function(path, expires)
                            table.insert(signed, { path, expires })

                            return '/storage/' .. path .. '?signature=x'
                        end,
                    },
                    own = { driver = 's3', client = client },
                },
            },
        })
        .container()
        :get('files')

    t.assert_equals(store:disk():temporary_url('a.txt', 60), '/storage/a.txt?signature=x')
    t.assert_equals(signed, { { 'a.txt', 60 } })
    t.assert_equals(store:disk('own').backend.client.bucket, 'own-bucket')
    t.assert_equals(store:disk('s3').backend.client.bucket, 'tnt-live')

    -- Свой клиент и поля клиента в разделе вместе — непонятно, чей брать:
    -- отказ сборки называет поле, а не берёт одно из двух молча.
    local ok, err = pcall(applied, SERVICES, { files = { disks = { s3 = { client = client } } } })

    t.assert_equals(ok, false)
    t.assert_str_contains(tostring(err), 'настройки файлов.disks.s3: ключа «access_key» нет')
end

g.test_files_without_a_section_and_a_declaration_are_not_there = function()
    t.assert_equals(applied(nil).container():has('files'), false)
    t.assert_equals(applied(SERVICES, { files = false }).container():has('files'), false)

    local store = applied(nil, {
            files = { disks = { tmp = { driver = 'local', root = '/tmp' } } },
        })
        .container()
        :get('files')

    t.assert_equals(store.default, 'tmp')
    t.assert_error_msg_equals(
        'приложение: files должно быть table или false, получено string',
        framework.new,
        spec({ files = 'local' })
    )
end

g.test_a_wrong_files_section_is_refused_by_the_assembly = function()
    local ok, err = pcall(applied, nil, { files = { disks = { a = 'local' } } })

    t.assert_equals(ok, false)
    t.assert_str_contains(tostring(err), 'приложение test.app не собрано: ')
    t.assert_str_contains(
        tostring(err),
        'настройки файлов.disks.a.driver — одно из «local», «s3», а не nil'
    )

    ok, err = pcall(applied, nil, { files = { disks = { a = { driver = 's3', bucket = 'x' } } } })

    t.assert_equals(ok, false)
    t.assert_str_contains(tostring(err), 'настройки s3')

    -- Поле локального диска у ведра — чужое диску, и отказ говорит
    -- о диске, а не о клиенте S3, которому это поле незнакомо.
    local bucket = {
        driver = 's3',
        endpoint = 'http://127.0.0.1:19000',
        bucket = 'tnt-live',
        access_key = 'ключ',
        secret_key = 'тайна',
    }

    for field, value in pairs({ root = '/tmp', sign = tostring }) do
        local disk = table.copy(bucket)

        disk[field] = value
        ok, err = pcall(applied, nil, { files = { disks = { a = disk } } })

        t.assert_equals(ok, false)
        t.assert_str_contains(
            tostring(err),
            ('настройки файлов.disks.a: ключа «%s» нет, есть client, driver, prefix, url'):format(
                field
            )
        )
    end
end

g.test_a_wrong_setting_of_a_service_is_refused_without_a_place_in_the_framework = function()
    -- Чинить надо настройку, а не строку фреймворка: отказ применения
    -- несёт слово пакета и ни одного места в исходнике.
    local refused = {
        { { cache = { driver = 'bogus' } }, 'кэш: драйвера bogus нет, есть memory, space и redis' },
        {
            { throttle = { driver = 'bogus' } },
            'настройки.driver — одно из «memory», «redis», а не «bogus»',
        },
        {
            { files = { disks = { x = { driver = 'bogus' } } } },
            'настройки файлов.disks.x.driver — одно из «local», «s3», а не «bogus»',
        },
        {
            { files = { disks = { x = { driver = 's3', bucket = 'b' } } } },
            'настройки s3.access_key — непустая строка, а не nil',
        },
    }

    for _, case in ipairs(refused) do
        t.assert_error_msg_equals(
            'приложение test.app не собрано: ' .. case[2],
            applied,
            nil,
            case[1]
        )
    end
end
