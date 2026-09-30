--- Собранное заранее: `bootstrap/cache/`.
---
--- Настройки собираются из `config/` и окружения один раз и ложатся файлом
--- `bootstrap/cache/config.lua`; пока он на месте, приложение берёт разделы
--- из него и окружение не читает — правка переменной без пересборки файла
--- ничего не меняет. Страницы переводятся в `bootstrap/cache/views/`:
--- ошибка шаблона обнаруживается здесь, а не на первом запросе. Переводит
--- их движок приложения, собранного вне узла, — со своими директивами
--- провайдеров. `clear` убирает и то и другое.
---
--- Маршруты собирать заранее нечего: они объявляются один раз
--- на применение конфигурации, а не на запрос.
---
---     tt run -e "require('tnt.framework.bootstrap').config()"
---     tt run -e "require('tnt.framework.bootstrap').views()"
---     tt run -e "require('tnt.framework.bootstrap').clear()"

local fio = require('fio')

local config_file = require('tnt.config')
local env = require('tnt.env')
local kernel_settings = require('tnt.kernel.settings')
local template = require('tnt.template')

local config_of = require('tnt.framework.config')
local files = require('tnt.framework.files')

--- Отказ — словом, без места в коде.
local fail = require('tnt.must.fail').raise

local Module = {}

--- Файл собранных настроек от корня приложения.
Module.CONFIG = 'bootstrap/cache/config.lua'

--- Каталог переведённых страниц от корня приложения.
Module.VIEWS = 'bootstrap/cache/views'

--- Модуль приложения от корня раскладки.
Module.APP = 'bootstrap/app'

--- Путь от корня приложения.
---@param base string|nil
---@param relative string
---@return string
local function place(base, relative)
    if base == nil or base == '.' then
        return relative
    end

    return base .. '/' .. relative
end

--- Собирает настройки из `config/` и окружения в `bootstrap/cache/config.lua`.
---
--- Тайны из окружения ложатся в файл открытым текстом: файл не для
--- репозитория, и права у него — только владельцу. В отказе же приведения
--- они прячутся, в том числе по подсказкам журнала (`log.secret_hints`).
---
--- Пишет `tnt.config`: файл подменяется целиком, и оборванная сборка
--- оставляет прежний файл, а не половину нового, — узел, поднятый
--- посреди сборки, иначе читал бы обрезанные настройки.
---@param base string|nil Корень приложения; по умолчанию рабочий каталог
---@return string path Куда записано
function Module.config(base)
    local directory = place(base, 'config')

    if not fio.path.is_dir(directory) then
        fail(('каталога настроек %s нет'):format(directory))
    end

    -- Файлы грузятся раньше связки, как и у ядра, где они читаются
    -- при загрузке роли, а связка идёт на применении: из кода приложения
    -- `tt run` грузит только их, и тайну журналу, объявленную в файле
    -- настроек, связка обязана увидеть.
    local loaded = config_of.files(directory)

    -- Сборка идёт из `tt run`, мимо применения конфигурации, где
    -- подсказки журнала в список окружения дописывает ядро. Без связки
    -- опечатка в переменной, которую тайной объявил только журнал,
    -- вынесла бы её значение в терминал и в журнал сборки.
    kernel_settings.link_secret_hints()
    env.configure()

    local sections = config_of.sections_of(loaded)(env)
    local path = place(base, Module.CONFIG)

    -- Под `pcall`: отказ о настройках не данными уходит оператору
    -- в терминал сборки, и место в коде фреймворка ему ни к чему.
    local ok, written, err = pcall(config_file.write, path, sections, {
        comment = 'Собрано tnt.framework.bootstrap.config: окружение не читается, пока файл на месте.',
    })

    if not ok then
        fail(written)
    end

    if written == nil then
        fail(tostring(err))
    end

    return path
end

--- Движок страниц приложения, собранного вне узла; пусто — модуля
--- приложения нет либо страниц у него нет.
---
--- Модуль грузится по имени, как его грузит ядро на старте: корень
--- приложения лежит на `package.path`.
---@param base string|nil
---@return TntTemplateEngine|nil
local function application_view(base)
    if not fio.path.is_file(place(base, Module.APP .. '.lua')) then
        return nil
    end

    local module = files.module_of(base or '.', Module.APP)
    local role = require(module)

    if type(role) ~= 'table' or type(role.offline_view) ~= 'function' then
        fail(('модуль приложения %s — не роль tnt.framework'):format(module))
    end

    return role.offline_view()
end

--- Переводит страницы в `bootstrap/cache/views`.
---
--- Переводит движок приложения из `bootstrap/app.lua`, собранного вне узла:
--- приложение поднимается с провайдерами, и директивы, которые заводят они,
--- переводятся вызовом, а не текстом. Каталог страниц и место
--- переведённого — его же. Без модуля приложения либо без страниц у него
--- переводится `resources/views` движком без своих директив; файл помнит
--- набор, и на старте движок с другим набором такой файл не берёт.
---@param base string|nil
---@return string[] names Что переведено
function Module.views(base)
    local views = application_view(base)
        or template.new({ path = place(base, 'resources/views'), compiled = place(base, Module.VIEWS) })

    -- Каталог есть у обоих движков: фреймворк заводит движок страниц
    -- только с каталогом.
    local directory = views.path --[[@as string]]

    if not fio.path.is_dir(directory) then
        fail(('каталога страниц %s нет'):format(directory))
    end

    return template.warm(views)
end

--- Убирает собранное заранее.
---@param base string|nil
---@return string[] removed Что убрано
function Module.clear(base)
    local removed = {}
    local config_path = place(base, Module.CONFIG)
    local views_path = place(base, Module.VIEWS)

    if fio.path.exists(config_path) then
        fio.unlink(config_path)
        table.insert(removed, config_path)
    end

    if fio.path.is_dir(views_path) then
        fio.rmtree(views_path)
        table.insert(removed, views_path)
    end

    -- Пустой каталог кэша не оставляется: пустое умолчание молчаливо.
    -- Непустой rmdir не тронет — и это ровно то, что нужно.
    fio.rmdir(place(base, 'bootstrap/cache'))

    return removed
end

return Module
