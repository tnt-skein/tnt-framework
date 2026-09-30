--- Наполнители `database/seeders/`: данные, без которых приложение пусто.
---
--- Схему поднимают миграции, а наполнитель кладёт в неё записи: справочник
--- состояний, первую учётку, клиентов для разработки. Файл `<имя>.lua`
--- возвращает наполнитель — функцию от контейнера приложения либо таблицу:
---
---     return {
---         after = { 'users' },   -- кто наполняет раньше: имена файлов
---         dev = true,            -- только для разработки
---         run = function(app)
---             …
---             return 3           -- сколько записей положено; можно ничего
---         end,
---     }
---
--- Имя наполнителя — имя файла: второго имени, которое разошлось бы
--- с первым, у него нет. Порядок — по зависимостям `after`, а среди
--- независимых — по имени: запуск не должен зависеть от того, как
--- `pairs` переберёт таблицу.
---
--- **Повтор не ломает.** Наполнитель обязан класть запись заменой по ключу
--- (`replace`, `put`, `save`), а не вставкой, которая на втором запуске
--- откажет «дубликат». Журнала выполненных наполнителей нет намеренно:
--- данные разработки перекладывают снова после каждой правки, и журнал
--- «уже наполнено» мешал бы ровно тогда, когда наполнение нужно.
---
--- **Только для разработки** — `dev = true`: такой наполнитель идёт,
--- только когда разработку попросили явно (`dev` у запуска), а в среде
--- `production` не идёт и тогда. Наполнитель без признака не вправе ждать
--- наполнителя разработки: без него он остался бы в бою без того, что ему
--- нужно, и это отказ при чтении каталога, а не в бою.
---
--- Файлы читаются по пути, как миграции: их никто не require-ит.

local files = require('tnt.framework.files')

--- Отказ без места вызова: текст уходит оператору в терминал.
local fail = require('tnt.must.fail').raise

--- Проверки по имени без броска: отказ о незнакомом ключе и не том
--- виде — общий со всеми пакетами.
local explain = require('tnt.must').explain

local Module = {}

--- Среда, где наполнители разработки не идут никогда.
Module.PRODUCTION = 'production'

--- Ключи наполнителя-таблицы.
local KEYS = { run = 'callable', after = { '?array_of', 'string' }, dev = '?boolean' }

---@class TntFrameworkSeeder
---@field name string Имя — имя файла без `.lua`
---@field run fun(app: TntDiContainer): (number|nil, string|nil) Наполняет; отдаёт число записей либо отказ
---@field after string[] Кто наполняет раньше
---@field dev boolean Только для разработки

--- Проверенный наполнитель файла.
---@param file { name: string, path: string }
---@param declared any Что вернул файл
---@return TntFrameworkSeeder
local function checked(file, declared)
    local what = ('приложение: наполнитель %s'):format(file.path)

    if type(declared) == 'function' then
        declared = { run = declared }
    end

    if type(declared) ~= 'table' then
        fail(
            ('%s должен вернуть функцию от контейнера либо таблицу { run, after, dev }'):format(
                what
            )
        )
    end

    local complaint = explain.options(declared, what, KEYS)

    if complaint ~= nil then
        fail(complaint)
    end

    return { name = file.name, run = declared.run, after = declared.after or {}, dev = declared.dev == true }
end

--- Наполнители по порядку зависимостей: зависимость раньше того, кто её
--- ждёт, а среди независимых — по имени.
---@param declared table<string, TntFrameworkSeeder>
---@param names string[] Имена по алфавиту
---@return TntFrameworkSeeder[]
local function ordered(declared, names)
    local order = {}
    local done = {}
    local visiting = {}

    ---@param name string
    ---@param path string[] Цепочка ожидания до этого имени
    local function visit(name, path)
        table.insert(path, name)

        if visiting[name] then
            fail(
                ('приложение: наполнители ждут друг друга по кругу: %s'):format(
                    table.concat(path, ' → ')
                )
            )
        end

        if not done[name] then
            visiting[name] = true

            for _, dependency in ipairs(declared[name].after) do
                visit(dependency, path)
            end

            visiting[name] = nil
            done[name] = true
            table.insert(order, declared[name])
        end

        table.remove(path)
    end

    for _, name in ipairs(names) do
        visit(name, {})
    end

    return order
end

--- Наполнители каталога по порядку запуска.
---
--- Негодный файл, зависимость, которой нет, круг зависимостей и боевой
--- наполнитель, ждущий наполнителя разработки, — ошибка с именем файла:
--- каталог правят руками, и чинить его надо до запуска.
---@param directory string
---@return TntFrameworkSeeder[]
function Module.of(directory)
    ---@type table<string, TntFrameworkSeeder>
    local declared = {}
    local names = {}

    for _, file in ipairs(files.of(directory, 'наполнителей')) do
        declared[file.name] = checked(file, dofile(file.path))
        table.insert(names, file.name)
    end

    for _, name in ipairs(names) do
        for _, dependency in ipairs(declared[name].after) do
            local needed = declared[dependency]

            if needed == nil then
                fail(
                    ('приложение: наполнитель %s ждёт %s, а такого в %s нет'):format(
                        name,
                        dependency,
                        directory
                    )
                )
            end

            if needed.dev and not declared[name].dev then
                fail(
                    ('приложение: наполнитель %s идёт и в production, а ждёт %s — наполнитель разработки'):format(
                        name,
                        dependency
                    )
                )
            end
        end
    end

    return ordered(declared, names)
end

---@class TntFrameworkSeedOptions
---@field only string[]|nil Какие наполнители запустить — вместе с теми, кого они ждут; по умолчанию все
---@field dev boolean|nil Запускать ли наполнители разработки
---@field environment string|nil Имя среды: в `production` наполнители разработки не идут

---@class TntFrameworkSeedReport
---@field seeded { name: string, count: number|nil }[] Что наполнено, по порядку
---@field skipped string[] Наполнители разработки, которых не просили

--- Кого запускать: названных и тех, кого они ждут.
---@param seeders TntFrameworkSeeder[]
---@param only string[]|nil
---@return table<string, boolean>|nil chosen
---@return string|nil err
local function chosen_of(seeders, only)
    local by_name = {}
    local chosen = {}

    for _, seeder in ipairs(seeders) do
        by_name[seeder.name] = seeder
        chosen[seeder.name] = only == nil
    end

    local function take(name)
        chosen[name] = true

        for _, dependency in ipairs(by_name[name].after) do
            take(dependency)
        end
    end

    for _, name in ipairs(only or {}) do
        if by_name[name] == nil then
            return nil, ('наполнителя %s нет'):format(name)
        end

        take(name)
    end

    return chosen, nil
end

--- Текст отказа запуска: кто сорвался и кто успел до него.
---@param name string
---@param failure any Отказ либо брошенное
---@param seeded { name: string }[] Что наполнено до него
---@return string
local function refused(name, failure, seeded)
    local names = {}

    for _, entry in ipairs(seeded) do
        table.insert(names, entry.name)
    end

    -- Пустоту узнаёт склейка, а не первый элемент: так у проверки нет
    -- индекса, мутант которого прошёл бы при одном наполненном.
    local done = table.concat(names, ', ')

    return ('наполнитель %s не выполнен: %s; до него наполнили: %s'):format(
        name,
        tostring(failure),
        done ~= '' and done or 'никого'
    )
end

--- Запускает наполнители по порядку.
---
--- Наполнитель отказывает парой `nil, err` либо бросает — запуск стоит
--- на нём, и отказ называет, кто успел до него: наполнение не транзакция,
--- и то, что положено, остаётся. Повтор после починки безопасен — на то
--- наполнители и кладут записи заменой.
---@param seeders TntFrameworkSeeder[] По порядку запуска (`of`)
---@param app TntDiContainer Контейнер приложения
---@param opts TntFrameworkSeedOptions|nil
---@return TntFrameworkSeedReport|nil report
---@return string|nil err
function Module.run(seeders, app, opts)
    opts = opts or {}

    if opts.dev and opts.environment == Module.PRODUCTION then
        return nil, 'наполнители разработки в среде production не запускаются'
    end

    local chosen, unknown = chosen_of(seeders, opts.only)

    if chosen == nil then
        return nil, unknown
    end

    local report = { seeded = {}, skipped = {} }

    for _, seeder in ipairs(seeders) do
        if chosen[seeder.name] and seeder.dev and not opts.dev then
            table.insert(report.skipped, seeder.name)
        elseif chosen[seeder.name] then
            local ok, count, err = pcall(seeder.run, app)

            if not ok then
                return nil, refused(seeder.name, count, report.seeded)
            end

            if not count and err ~= nil then
                return nil, refused(seeder.name, err, report.seeded)
            end

            table.insert(report.seeded, { name = seeder.name, count = type(count) == 'number' and count or nil })
        end
    end

    return report, nil
end

return Module
