--- Наполнение и состояние схемы у роли приложения: `role.seed`
--- и `role.migrations`, — и команды узла на них: `db:seed`
--- и `migrate:status`.
---
--- Обоим нужен живой узел: наполнителю — контейнер применённой роли
--- со службами, состоянию — спейсы с версией и журналом шагов. Поэтому
--- это методы роли, а не команды вне узла. Оператор зовёт их командами
--- узла — сценарием `console.lua` через функцию iproto роли
--- (`tnt.framework.commands`):
---
---     tarantool console.lua db:seed --dev
---     tarantool console.lua migrate:status --json
---
--- Ответ метода — таблица для кода, текст для человека (`format = 'text'`)
--- либо строка JSON (`format = 'json'`) для другой программы. Отказ — пара
--- `nil, err`, как везде; негодные настройки вызова — бросок со строкой
--- вызывающего: это ошибка в коде, который зовёт метод. У команды отказ —
--- код выхода 1 и причина в поток ошибок.

local json = require('json')
local must = require('tnt.must')
local output = require('tnt.console.output')
local schema = require('tnt.schema')

local migrations_of = require('tnt.framework.migrations')
local seeders_of = require('tnt.framework.seeders')

local Module = {}

--- Виды ответа, кроме таблицы.
local FORMATS = { 'text', 'json' }

--- Настройки наполнения.
local SEED_OPTIONS = {
    only = { '?array_of', 'string' },
    dev = '?boolean',
    format = { '?one_of', FORMATS },
}

--- Настройки состояния схемы.
local STATUS_OPTIONS = { format = { '?one_of', FORMATS } }

--- Метка списка для JSON: пустой список иначе ушёл бы объектом `{}`.
local SEQUENCE = { __serialize = 'seq' }

--- Поля-списки отчёта наполнения и состояния схемы: в JSON они списки
--- и пустыми.
local SEED_LISTS = { 'seeded', 'skipped' }
local STATUS_LISTS = { 'steps' }

--- Ключ ответа другой программе — один у всех команд узла.
local JSON = {
    name = 'json',
    description = 'ответ строкой JSON для другой программы',
    flag = true,
}

--- Текст, нарисованный выводом команд: таблица выровнена по знакам,
--- а не по байтам, — столбец с кириллицей не уезжает.
---@param draw fun(out: TntConsoleOutput)
---@return string
local function drawn(draw)
    local lines = {}

    local function write(text)
        table.insert(lines, text)
    end

    draw(output.new(write, write))

    return table.concat(lines)
end

--- Отчёт наполнения человеку: кто наполнил сколько, кого пропустили.
---@param out TntConsoleOutput
---@param report TntFrameworkSeedReport
local function seed_lines(out, report)
    local rows = {}

    for _, entry in ipairs(report.seeded) do
        table.insert(rows, { entry.name, entry.count or '' })
    end

    if rows[1] == nil then
        out:line('наполнять нечего')
    else
        out:table({ 'наполнитель', 'записей' }, rows)
    end

    if report.skipped[1] ~= nil then
        out:line(
            'пропущены наполнители разработки: %s',
            table.concat(report.skipped, ', ')
        )
    end
end

---@class TntFrameworkMigrationStep: TntSchemaStep
---@field file string|nil Имя файла миграции без `.lua`

---@class TntFrameworkMigrationStatus: TntSchemaStatus
---@field steps TntFrameworkMigrationStep[]

--- Состояние шага словом.
---@param step TntSchemaStep
---@return string
local function state_of(step)
    if step.applied then
        return step.registered and 'применён' or 'применён, нет в коде'
    end

    return step.registered and 'ждёт' or 'нет в коде'
end

--- Состояние схемы человеку: строка узла и таблица шагов. Время — UTC:
--- узлы кластера живут в разных поясах, а сравнивать их записи надо
--- между собой.
---@param out TntConsoleOutput
---@param status TntFrameworkMigrationStatus
local function status_lines(out, status)
    out:line('узел %s: версия в базе %d, в коде %d', status.instance, status.current, status.target)

    local rows = {}

    for _, step in ipairs(status.steps) do
        local row = { step.version, step.file or '', state_of(step) }

        if step.applied_at ~= nil then
            table.insert(row, os.date('!%Y-%m-%d %H:%M:%S', math.floor(step.applied_at)))
            table.insert(row, step.instance)
            table.insert(row, ('%.1f'):format(step.elapsed_ms))
        end

        table.insert(rows, row)
    end

    if rows[1] ~= nil then
        out:table({ 'шаг', 'файл', 'состояние', 'применён (UTC)', 'узел', 'мс' }, rows)
    end
end

--- Строка JSON для другой программы.
---@param value table
---@param lists string[] Поля-списки: в JSON они списки и пустыми
---@return string
local function encoded(value, lists)
    for _, key in ipairs(lists) do
        setmetatable(value[key], SEQUENCE)
    end

    return json.encode(value)
end

--- Ответ метода в нужном виде: таблица, текст или JSON.
---@param value table
---@param format string|nil
---@param draw fun(out: TntConsoleOutput, value: table)
---@param lists string[] Поля-списки: в JSON они списки и пустыми
---@return table|string
local function rendered(value, format, draw, lists)
    if format == 'text' then
        return drawn(function(out)
            draw(out, value)
        end)
    end

    if format == 'json' then
        return encoded(value, lists)
    end

    return value
end

--- Ответ команды в вывод: строка JSON другой программе, текст человеку.
---@param out TntConsoleOutput
---@param value table
---@param as_json boolean
---@param draw fun(out: TntConsoleOutput, value: table)
---@param lists string[] Поля-списки: в JSON они списки и пустыми
local function answered(out, value, as_json, draw, lists)
    if as_json then
        out:line(encoded(value, lists))
    else
        draw(out, value)
    end
end

--- Даёт роли методы наполнения и состояния схемы.
---@param role table Роль ядра: у неё берётся контейнер применения
---@param name string Имя приложения — для текста отказа
---@param seeders string|nil Каталог наполнителей
---@param migrations string|nil Каталог миграций
function Module.attach(role, name, seeders, migrations)
    --- Наполняет базу наполнителями каталога `database/seeders`.
    ---
    --- Каталог читается на каждом вызове: правка наполнителя видна без
    --- перезапуска узла. Среда — `TNT_ENV` из окружения приложения.
    ---@param opts { only: string[]|nil, dev: boolean|nil, format: string|nil }|nil
    ---@return TntFrameworkSeedReport|string|nil report
    ---@return string|nil err
    role.seed = function(opts)
        must.at(2).optional.options(opts, 'настройки наполнения', SEED_OPTIONS)
        opts = opts or {}

        local app = role.container()

        if app == nil then
            return nil,
                ('приложение %s на этом узле не применено: наполнять нечем'):format(
                    name
                )
        end

        if seeders == nil then
            return nil,
                ('у приложения %s нет каталога наполнителей database/seeders'):format(
                    name
                )
        end

        local report, err = seeders_of.run(seeders_of.of(seeders), app, {
            only = opts.only,
            dev = opts.dev,
            environment = app:get('env').status().environment,
        })

        if report == nil then
            return nil, err
        end

        return rendered(report, opts.format, seed_lines, SEED_LISTS)
    end

    --- Состояние схемы этого узла: какие шаги применены, какие ждут,
    --- когда и каким узлом применены, с именами файлов миграций.
    ---@param opts { format: string|nil }|nil
    ---@return TntFrameworkMigrationStatus|string|nil status
    ---@return string|nil err
    role.migrations = function(opts)
        must.at(2).optional.options(opts, 'настройки состояния схемы', STATUS_OPTIONS)
        opts = opts or {}

        local found, err = schema.status()

        if found == nil then
            return nil, err
        end

        ---@type TntFrameworkMigrationStatus
        local status = found

        local files = migrations ~= nil and migrations_of.names(migrations) or {}

        for _, step in ipairs(status.steps) do
            step.file = files[step.version]
        end

        return rendered(status, opts.format, status_lines, STATUS_LISTS)
    end
end

--- Объявляет команды узла `db:seed` и `migrate:status` на методах роли.
---
--- Команда зовёт метод без `format` и рисует таблицу сама — прямо
--- в свой вывод: текст для человека и строка JSON для другой программы
--- выходят те же, что у метода с `format`.
---@param app TntConsoleApp Команды роли
---@param role TntFrameworkRole Роль, у которой уже есть `seed` и `migrations`
function Module.commands(app, role)
    app:command('db:seed', {
        description = 'Наполнить базу наполнителями database/seeders\n'
            .. 'Наполнители разработки идут только с ключом --dev и не идут в среде production.',
        options = {
            { name = 'dev', description = 'и наполнители разработки', flag = true },
            {
                name = 'only',
                description = 'только этот наполнитель и те, кого он ждёт; можно несколько раз',
                many = true,
            },
            JSON,
        },
        handler = function(input, out)
            local report, err = role.seed({ dev = input.dev, only = input.only[1] ~= nil and input.only or nil })

            if report == nil then
                return nil, err
            end

            answered(out, report --[[@as table]], input.json, seed_lines, SEED_LISTS)
        end,
    })

    app:command('migrate:status', {
        description = 'Какие шаги схемы применены на этом узле, когда и каким узлом',
        options = { JSON },
        handler = function(input, out)
            local status, err = role.migrations()

            if status == nil then
                return nil, err
            end

            answered(out, status --[[@as table]], input.json, status_lines, STATUS_LISTS)
        end,
    })
end

return Module
