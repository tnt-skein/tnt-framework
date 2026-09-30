--- Приложение, собранное вне узла, — для того, что собирается заранее.
---
--- Как на старте до провайдеров и `build` включительно, но без узла: ни
--- сервера HTTP, ни сети, ни применения конфигурации. Перевод страниц
--- заранее без этого не обойдётся: свои директивы заводят провайдеры, и
--- перевод без них положил бы `@директиву` в кэш текстом.
---
--- Стандартные имена контейнера — те же, что ядро кладёт до `build`
--- (`config`, `settings`, `env`, `log`, `clock`, см. `tnt.kernel`),
--- кроме `http`: сервера вне узла нет, и спросивший его получит внятный
--- отказ контейнера, а не чужой сервер.

local clock = require('tnt.clock')
local di = require('tnt.di')
local env = require('tnt.env')
local kernel_settings = require('tnt.kernel.settings')
local logging = require('tnt.log')

--- Отказ без места вызова: текст уходит в терминал сборки.
local fail = require('tnt.must.fail').raise

local Module = {}

--- Настройки вне узла: разделы приложения — те же, что на старте.
---
--- Разделы читаются, как их читает ядро на применении: связка тайн
--- журнала — до чтения окружения, иначе отказ приведения показал бы
--- в терминале значение тайны. Места узла в кластере вне узла нет:
--- `instance`, `replicaset` и `group` пусты, узел не объявлен ни роутером,
--- ни хранилищем, а настройки роли (`roles_cfg`) и метки — пустые таблицы,
--- чтобы провайдер, читающий их, не падал на пустоте.
---@param sections (fun(env: TntEnv): table<string, table>)|nil Разделы из `config/` либо собранного файла
---@return TntKernelConfig
local function config_of(sections)
    ---@type any
    local config = { role = {}, labels = {}, is_router = false, is_storage = false }

    if sections ~= nil then
        kernel_settings.link_secret_hints()
        env.configure()

        for name, section in pairs(sections(env)) do
            config[name] = section
        end
    end

    return config
end

--- Собирает приложение вне узла: стандартные имена, затем `declare`.
---
--- Сорвавшаяся сборка закрывает то, что успела создать, и отказывает
--- с именем приложения; тайны из отказа сборщика прячутся, как их прячет
--- ядро в alerts: текст уходит в терминал и журнал сборки. Собранный
--- контейнер закрывает тот, кто его просил.
---@param name string Имя приложения — журнал и текст отказа
---@param sections (fun(env: TntEnv): table<string, table>)|nil Разделы настроек
---@param declare fun(app: TntDiContainer, config: TntKernelConfig) Объявления фреймворка и приложения
---@return TntDiContainer
function Module.assembled(name, sections, declare)
    local app = di.new()

    local ok, err = pcall(function()
        local config = config_of(sections)

        app:value('config', config)
        app:value('settings', kernel_settings.readable(config))
        app:value('env', env)
        app:value('log', logging.new(name))
        app:value('clock', clock)

        declare(app, config)
    end)

    if not ok then
        app:close()
        fail(
            ('приложение %s не собрано вне узла: %s'):format(
                name,
                logging.scrub(tostring(err))
            )
        )
    end

    return app
end

return Module
