--- Службы приложения по разделам настроек.
---
---     config/redis.lua      redis      клиент tnt-redis
---     config/database.lua   db         драйвер tnt-postgres либо tnt-mysql — поле driver
---     config/cache.lua      cache      кэш tnt-cache; без раздела — в памяти
---     config/throttle.lua   throttle   ограничитель tnt-throttle; без раздела — в памяти
---     config/mail.lua       mail       почта tnt-mail, настроенная разделом
---     config/files.lua      files      диски tnt-files; у диска s3 — клиент tnt-s3 из его полей
---
--- Контейнер берёт приложение, а не пакет: связь между пакетами передаётся
--- здесь, аргументом. Кэшу и ограничителю на драйвере `redis` без своего
--- клиента в объявлении достаётся клиент раздела `redis` — один на
--- приложение, с одним пулом соединений, а не по пулу на каждого.
---
--- Клиент Redis и драйвер базы — синглтоны: собираются первым обращением
--- и закрываются вместе с контейнером, то есть на перечитывании
--- конфигурации и останове. Узел, которому база не понадобилась,
--- соединений не заводит, а рок `pg` ему не нужен вовсе. Кэш, ограничитель
--- и почта собираются при применении: их настройки проверяются сразу,
--- и опечатка видна оператору в alerts, а не первым запросом. Кэш
--- на спейсе при этом спейса не ищет: спейс заводит шаг миграции,
--- а миграции ядро поднимает событием после применения, и на пустой базе
--- кэш находит спейс первым обращением, а не роняет применение.
---
--- Диски — тоже при применении: клиент S3 в сеть не ходит, пока его
--- не позвали, а негодный ключ настроек диска виден сразу.

local cache = require('tnt.cache')
local files = require('tnt.files')
local throttle = require('tnt.throttle')

--- Отказ без места вызова: текст уходит оператору в alerts.
local fail = require('tnt.must.fail').raise

--- Проверки по имени без броска: текст отказа общий со всеми пакетами.
local explain = require('tnt.must').explain

local Module = {}

--- Имена служб в контейнере.
Module.REDIS = 'redis'
Module.DB = 'db'
Module.CACHE = 'cache'
Module.THROTTLE = 'throttle'
Module.MAIL = 'mail'
Module.FILES = 'files'

--- Драйверы базы по полю `driver` раздела `database`.
Module.DATABASES = { 'mysql', 'postgres' }

--- Пакеты драйверов базы. Грузятся, только когда раздел назвал драйвер:
--- узлу без базы они не нужны.
local DRIVERS = {
    mysql = function()
        return require('tnt.mysql')
    end,
    postgres = function()
        return require('tnt.postgres')
    end,
}

--- Служба по настройкам — с отказом без места в исходнике.
---
--- Негодные настройки пакет отвергает броском со строкой вызывающего,
--- а вызывающий здесь — фреймворк: место в отказе указало бы на его
--- строку, а чинить надо настройку. Конструктор зовётся под `pcall` сам,
--- без обёртки: вина уходит на `pcall`, и места в тексте нет, — оператор
--- видит в alerts одно слово пакета.
---@generic T
---@param new fun(options: any): T Конструктор службы
---@param options any Настройки
---@return T
local function built(new, options)
    local ok, service = pcall(new, options)

    if not ok then
        fail(tostring(service))
    end

    return service
end

--- Закрывает клиента вместе с контейнером.
---@param client { close: fun(self: any): any }
local function closed(client)
    client:close()
end

--- Настройки службы: объявление, поверх него — раздел настроек.
---
--- Драйверу `redis` без своего клиента — клиент приложения из раздела
--- `redis`. Клиент — не настройка, разделу его не передать, а без раздела
--- `redis` взять его неоткуда: это отказ сборки, а не служба, которая
--- откажет первым же вызовом.
---@param app TntDiContainer
---@param field string Поле объявления и раздел настроек — для отказа
---@param declared table|nil Что объявлено
---@param section any Раздел настроек
---@return table
local function options_of(app, field, declared, section)
    ---@type any
    local options = {}

    for key, value in pairs(declared or {}) do
        options[key] = value
    end

    for key, value in pairs(type(section) == 'table' and section or {}) do
        options[key] = value
    end

    if options.driver == 'redis' and options.redis == nil then
        if not app:has(Module.REDIS) then
            fail(
                ('приложение: %s: драйверу redis нужен клиент — '):format(field)
                    .. ('раздел redis настроек либо %s.redis в объявлении'):format(field)
            )
        end

        options.redis = app:get(Module.REDIS)
    end

    return options
end

--- Сборщик драйвера базы по разделу `database`.
---
--- Раздел без `driver` — не база SQL: так пишут настройки хранения самого
--- Tarantool (шардирование, каталог миграций), и драйвера у них нет.
--- Настройки драйвера — раздел без `driver`.
---@param section any Раздел `database`
---@return (fun(): any)|nil
local function database_of(section)
    local driver = type(section) == 'table' and section.driver or nil

    if driver == nil then
        return nil
    end

    local complaint = explain.kind(driver, 'приложение: database.driver', 'one_of', Module.DATABASES)

    if complaint ~= nil then
        fail(complaint)
    end

    local load = DRIVERS[driver]

    ---@type any
    local options = table.copy(section)

    options.driver = nil

    return function()
        return load().new(options)
    end
end

--- Поля диска, которые читает сам `tnt-files`. Остальные поля диска `s3`
--- — настройки клиента `tnt-s3`: ключи, узел, ведро, срок.
---
--- Поля локального диска здесь тоже: у диска `s3` они остаются диску,
--- и отказ называет их чужими диску, а не незнакомыми клиенту S3.
---@type table<string, boolean>
local DISK_FIELDS = { driver = true, root = true, url = true, sign = true, prefix = true }

--- Таблица как есть, прочее — пусто: вид раздела проверяет `tnt-files`,
--- и его отказ назовёт поле, а не упадёт на обходе строки.
---@param value any
---@return table
local function table_or_empty(value)
    return type(value) == 'table' and value or {}
end

--- Диск: объявление, поверх него — раздел; у диска `s3` без клиента —
--- клиент из его полей.
---
--- Клиент — не настройка, и в раздел его не положить; зато настройки
--- клиента — строки и числа, и раздел их несёт. Свой клиент диску дают
--- объявлением, `client = bucket`, — тогда поля клиента в разделе не нужны.
---@param declared any
---@param section any
---@return table
local function disk_of(declared, section)
    local merged = {}

    for _, source in ipairs({ table_or_empty(declared), table_or_empty(section) }) do
        for key, value in pairs(source) do
            merged[key] = value
        end
    end

    if merged.driver ~= 's3' or merged.client ~= nil then
        return merged
    end

    local disk, settings = {}, {}

    for key, value in pairs(merged) do
        if DISK_FIELDS[key] then
            disk[key] = value
        else
            settings[key] = value
        end
    end

    disk.client = built(require('tnt.s3').new, settings)

    return disk
end

--- Настройки дисков: объявление, поверх него — раздел, по диску.
---
--- Сливаются диски по именам, а не разделы целиком: функцию подписи
--- `sign` локальному диску даёт объявление (в раздел её не положить),
--- а каталог и адрес — раздел, и одно не должно затирать другое.
---@param declared table Объявление
---@param section any Раздел `files`
---@return TntFilesOptions
local function files_of(declared, section)
    section = table_or_empty(section)

    local mine, theirs = table_or_empty(declared.disks), table_or_empty(section.disks)
    local disks = {}

    for _, source in ipairs({ mine, theirs }) do
        for name in pairs(source) do
            disks[name] = disk_of(mine[name], theirs[name])
        end
    end

    return { default = section.default or declared.default, disks = disks }
end

---@class TntFrameworkServicesSpec Поля объявления приложения, из которых собираются службы
---@field cache TntCacheOptions|false|nil
---@field throttle TntThrottleOptions|false|nil
---@field files TntFilesOptions|false|nil

--- Объявляет службы по разделам настроек и объявлению приложения.
---
--- Клиент Redis — первым: кэш и ограничитель берут его при сборке.
---@param app TntDiContainer
---@param config table Разделы настроек
---@param spec TntFrameworkServicesSpec Объявление
function Module.declare(app, config, spec)
    local redis = config.redis

    if redis ~= nil then
        app:single(Module.REDIS, function()
            return require('tnt.redis').new(redis)
        end, { close = closed })
    end

    local database = database_of(config.database)

    if database ~= nil then
        app:single(Module.DB, database, { close = closed })
    end

    if spec.cache ~= false then
        app:value(Module.CACHE, built(cache.new, options_of(app, Module.CACHE, spec.cache, config.cache)))
    end

    if spec.throttle ~= false then
        app:value(
            Module.THROTTLE,
            built(throttle.new, options_of(app, Module.THROTTLE, spec.throttle, config.throttle))
        )
    end

    -- Без раздела и без объявления дисков нет: каталог по умолчанию
    -- завёл бы файлы там, где их никто не ждёт.
    if spec.files ~= false and (spec.files ~= nil or config.files ~= nil) then
        app:value(Module.FILES, built(files.new, files_of(spec.files or {}, config.files)))
    end

    -- Настройки почты общие на процесс, как у трассы: раздел отдаётся
    -- пакету на каждом применении. Без раздела фреймворк почту не трогает —
    -- её вправе настроить само приложение.
    if config.mail ~= nil then
        local mail = require('tnt.mail')

        mail.configure(config.mail)
        app:value(Module.MAIL, mail)
    end
end

return Module
