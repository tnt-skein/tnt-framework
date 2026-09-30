--- Каталог миграций `database/migrations/`: шаги схемы по номерам версий.
---
--- Файлы читаются по пути, а не модулем: их никто не require-ит,
--- а рабочий каталог узла не обязан быть корнем приложения.
---
--- Здесь же заводится новый файл: `create('orders')` кладёт в каталог
--- `NNN_orders.lua` со следующим номером и шапкой шага. Номер считается
--- по каталогу, а не набирается руками: два шага с одним номером реестр
--- не примет, а пропуск в нумерации остановит подъём.

local fio = require('fio')

local declaration = require('tnt.kernel.spec')
local files = require('tnt.framework.files')

--- Отказ без места вызова: текст уходит оператору в alerts.
local fail = require('tnt.must.fail').raise

local Module = {}

--- Файлы миграций каталога с номерами версий.
---
--- Номер — приставка имени файла: `001_customers.lua`, — и это номер
--- версии схемы, до которой шаг поднимает базу. Файл без номера — ошибка
--- с его именем: он не шаг, а опечатка, и молча пропущенный он оставил бы
--- схему без изменения.
---@param directory string
---@return { version: integer, name: string, path: string }[]
local function numbered(directory)
    local found = {}

    for _, file in ipairs(files.of(directory, 'миграций')) do
        -- Цифры — «цифра и сколько угодно ещё», а не `%d+`: перед `_`
        -- мутанты `%d-` и `%d*` берут те же цифры, а пустой захват
        -- tonumber сводит к тому же nil. У этой записи мутант один —
        -- `%d%d+`, — и его ловит номер из одной цифры.
        local version = tonumber(file.name:match('^(%d%d*)_'))

        if version == nil then
            fail(
                ('приложение: миграция %s должна начинаться с номера версии: 001_имя.lua'):format(
                    file.path
                )
            )
        end

        table.insert(found, { version = version, name = file.name, path = file.path })
    end

    return found
end

--- Шаги миграций каталога по номерам версий.
---
--- Порядок шагов держится версией (см. `numbered`). Отката нет, и каждый
--- шаг обязан читаться кодом прежней версии: инстансы обновляются
--- по одному (см. `tnt.schema`). Путь — относительно рабочего каталога
--- узла либо абсолютный.
---
--- Файл возвращает шаг `function(box)` либо таблицу `{ step = шаг,
--- slice = секунды }` — долгому шагу срез файбера сверх секунды ядра.
--- Форма та же, что у поля `migrations` ядра, и проверяет её ядро же:
--- здесь только называется файл, а не номер версии.
---@param directory string
---@return table<integer, TntKernelMigration>
function Module.of(directory)
    local steps = {}

    for _, entry in ipairs(numbered(directory)) do
        local migration = dofile(entry.path)

        declaration.checked_migration(entry.path, migration)

        steps[entry.version] = migration
    end

    return steps
end

--- Имена файлов миграций по номерам версий — для состояния схемы:
--- номер шага человеку мало что говорит, имя файла — говорит.
---
--- Файлы не исполняются: состояние читают и там, где шаги уже отданы.
---@param directory string
---@return table<integer, string> names Имя файла без `.lua`
function Module.names(directory)
    local names = {}

    for _, entry in ipairs(numbered(directory)) do
        names[entry.version] = entry.name
    end

    return names
end

--- Каталог миграций по соглашению — от корня приложения.
Module.DIRECTORY = 'database/migrations'

--- Имя новой миграции: строчные латинские буквы, цифры и `_`, с буквы.
---
--- Имя уходит в имя файла, а файл — в имя модуля при чтении по пути:
--- точка, косая черта и пробел в нём сломали бы одно либо другое.
local NAME = '^[a-z][a-z0-9_]*$'

--- Шапка нового файла. Тело шага пустое, и `box` в нём не тронут: линт
--- приложения скажет о неиспользованном аргументе, и пустой шаг
--- не уедет в коммит незамеченным.
local TEMPLATE = table.concat({
    '--- Версия %d: %s.',
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

--- Заводит файл миграции со следующим номером и шапкой шага.
---
--- Номер — наибольший в каталоге плюс один, три цифры: `002_orders.lua`.
--- Каталога нет — он заводится: первая миграция приложения его и создаёт.
--- Это команда оператора, и отказ у неё — бросок без места с текстом
--- для терминала, как у команд `tnt.framework.bootstrap`: `tt run -e`
--- с ним кончается ненулевым кодом, а пара `nil, err` прошла бы молча.
---@param name string Имя шага: `orders`, `add_status_to_orders`
---@param directory string|nil Каталог миграций; по умолчанию `database/migrations`
---@return string path Заведённый файл
function Module.create(name, directory)
    directory = directory or Module.DIRECTORY

    if type(name) ~= 'string' or name:match(NAME) == nil then
        fail(
            ('имя миграции — строчные латинские буквы, цифры и «_», с буквы, а не «%s»'):format(
                tostring(name)
            )
        )
    end

    if not fio.path.is_dir(directory) and not fio.mktree(directory) then
        fail(('каталог миграций %s не заведён'):format(directory))
    end

    local version = 0

    for _, entry in ipairs(numbered(directory)) do
        version = math.max(version, entry.version)
    end

    version = version + 1

    local path = fio.pathjoin(directory, ('%03d_%s.lua'):format(version, name))

    -- Только новый файл: чужой с тем же именем не затирается.
    local file, err = fio.open(path, { 'O_WRONLY', 'O_CREAT', 'O_EXCL' }, tonumber('644', 8))

    if file == nil then
        fail(('файл миграции %s не заведён: %s'):format(path, tostring(err)))
    end

    file:write(TEMPLATE:format(version, (name:gsub('_', ' '))))
    file:close()

    return path
end

--- Каталоги миграций, чьи шаги уже отданы ядру.
---
--- Реестр шагов у `tnt.schema` один на процесс, и шаг дважды он
--- не принимает: роль, заведённая повторно (проверки, перечитывание
--- модуля), отдавать те же файлы не должна.
---@type table<string, boolean>
local registered = {}

--- Шаги каталога для ядра — один раз на процесс.
---
--- Реестр шагов у `tnt.schema` один на процесс, и шаг дважды он
--- не принимает: роль, заведённая повторно (проверки, перечитывание
--- модуля), отдавать те же файлы не должна.
---@param directory string
---@return table<integer, TntKernelMigration>|nil steps Пусто — каталог уже отдан
function Module.once(directory)
    if registered[directory] then
        return nil
    end

    registered[directory] = true

    return Module.of(directory)
end

return Module
