--- Раскладка приложения поверх ядра `tnt.kernel`.
---
--- Ядро собирает роль Tarantool из функций и таблиц; здесь эти функции и
--- таблицы берутся из каталогов и списков приложения, а точкой входа служит
--- один модуль:
---
---     -- bootstrap/app.lua
---     return require('tnt.framework').new({ name = 'app', dependencies = { 'roles.httpd' } })
---
--- Раскладка находится по соглашению от корня `base` (по умолчанию —
--- рабочий каталог узла, то есть каталог приложения), и называть каждый
--- каталог отдельно не нужно:
---
---     config/                   настройки из окружения, файл на раздел
---     bootstrap/providers.lua   провайдеры по порядку
---     app/models/               модели tnt.model, файл на модель
---     database/migrations/      шаги схемы NNN_имя.lua
---     database/seeders/         наполнители, файл на наполнитель
---     routes/middleware.lua     слои, функция от контейнера
---     routes/iproto.lua         функции для lua_call
---     routes/<имя>.lua          маршруты HTTP, по алфавиту имён
---     resources/views/          страницы; errors/404 и рядом — отказы
---     lang/                     переводы, файл на язык: ru.lua, en.lua
---
--- Чего на месте нет — того и нет; явное поле объявления перебивает
--- соглашение. Что взято по соглашению, показывает `role.layout()`:
--- умолчание не должно быть молчаливым.
---
--- Раскладка ищется от `base`, а имена модулей в ней — от `prefix`.
--- Приложению в каталоге узла ни то, ни другое не нужно: корень — `.`,
--- и путь от него и есть имя модуля. Приложению, которое едет роком,
--- нужны оба: каталог рока находится по самому модулю, а имя модуля
--- из его пути не выводится.
---
---     return require('tnt.framework').new({
---         name = 'acme.board',
---         base = root,             -- каталог пакета: <рок>/acme/board
---         prefix = 'acme.board',   -- имя модуля того же каталога
---     })
---
--- Контейнер в приложении зовётся `app`.
---
--- Каталог настроек `config/`: каждый файл возвращает функцию от окружения
--- и отвечает таблицей, умолчания стоят рядом с именем переменной,
--- результат лежит в `config.<имя файла>`; окружение ядро перечитывает
--- на каждом применении. Файл `log.lua` ядро отдаёт встроенному журналу.
---
--- Провайдеры — это части `build`, `ready`, `routes` и `iproto` приложения,
--- разложенные по файлам; права пакету ходить в контейнер они не дают —
--- провайдер пишет само приложение. Список имён модулей
--- (`bootstrap/providers.lua`) задаёт порядок; каталог строкой — порядок по
--- имени файла. `build` и `ready` самого приложения идут после провайдеров:
--- у них последнее слово.
---
--- Миграции `database/migrations`: файл `NNN_имя.lua` возвращает шаг —
--- функцию от `box`, номер в имени — версия схемы; долгому шагу —
--- таблицу `{ step = шаг, slice = секунды }` со срезом файбера, как у поля
--- `migrations` ядра. Файлы читаются по пути, а не модулем: их никто
--- не require-ит, а рабочий каталог узла не обязан быть корнем приложения.
--- Что применено, когда и каким узлом, отвечает `role.migrations()`.
---
--- Наполнители `database/seeders`: файл `<имя>.lua` возвращает функцию
--- от контейнера либо `{ run, after, dev }`; запускает их `role.seed()`
--- на живом узле (`tnt.framework.seeders`, `tnt.framework.database`).
---
--- Команды узла `db:seed` и `migrate:status` роль публикует функцией
--- iproto `<имя>_command`: сценарий оператора `console.lua` зовёт её через
--- `console.remote` (`tnt-console`) под учёткой с правом только на эту
--- функцию и кончается тем кодом, которым команда кончилась на узле
--- (`tnt.framework.commands`).
---
--- Модели `app/models`: файл — модуль с моделью `tnt.model`. Список уходит
--- ядру: оно привязывает модели по месту узла при применении конфигурации.
--- Шаг схемы модели — файлом миграции через `Model.migration()`, порядок
--- версий принадлежит приложению.
---
--- У движка страниц — директива `@canonical(адрес)`: тег канонического
--- адреса по адресу из данных страницы (`tnt.framework.canonical`), —
--- и `@dump(значение)`: показ значения `tnt-debug` с тайнами под отметкой
--- (`tnt.framework.dump`).
---
--- Страницы отказов `resources/views/errors`: `404.thtml.lua` и рядом —
--- шаблон на код ответа, `error.thtml.lua` — общий на все остальные.
--- Их получает каталог отказов ядра, и браузеру, попросившему `text/html`,
--- отказ уходит страницей на рамке сайта; сценарию — прежним телом.
--- Чего нет, показывает встроенная страница `tnt-error`
--- (`tnt.framework.pages`).
---
--- Переводы `lang/`: файл на язык, язык по умолчанию — `app.locale`.
--- Переводчик `tnt-i18n` лежит в контейнере под именем `i18n`, у страниц
--- появляются директивы `@lang`, `@choice` и `@locale`, на входе
--- роутера — слой языка запроса по `Accept-Language`, а слово отказа
--- берётся строкой `errors.<код>` на языке запроса
--- (`tnt.framework.lang`).
---
--- Службы по разделам настроек: `config/redis.lua` — клиент Redis,
--- `config/database.lua` с полем `driver` — драйвер базы `db`, кэш,
--- ограничитель частоты и почта. Связь между пакетами — аргументом:
--- кэшу и ограничителю на драйвере redis достаётся клиент раздела
--- `redis` (`tnt.framework.services`).
---
--- Сессии — разделом `config/session.lua` либо полем `session`: менеджер
--- `tnt-session` лежит в контейнере под именем `session`, а его слой —
--- в реестре слоёв приложения и в группе `web`, которую маршрут страницы
--- берёт именем: `{ middleware = { 'web' } }` (`tnt.framework.session`).
--- Свои слои и группы реестра приложение объявляет полями `layers`
--- и `groups`; его группа `web` встаёт после слоя сессий — туда ложится
--- сверка токена `csrf`. Токен формы при сессиях ложится в данные каждой
--- страницы сам, а своё общее приложение кладёт туда полем `view_data`.
---
--- Межсайтовые запросы — полем `cors` либо разделом `app.cors`: слой
--- `cors` стоит первым на входе роутера, до поиска маршрута и выше режима
--- обслуживания, — предварительный `OPTIONS` получает ответ слоя, а не
--- роутера, и 503 закрытого приложения тоже несёт разрешение
--- (`tnt.framework.cors`).

local kernel = require('tnt.kernel')
local template = require('tnt.template')

local asset_of = require('tnt.framework.asset')
local canonical = require('tnt.framework.canonical')
local commands_of = require('tnt.framework.commands')
local config_of = require('tnt.framework.config')
local cors_of = require('tnt.framework.cors')
local database = require('tnt.framework.database')
local downtime_of = require('tnt.framework.downtime')
local dump = require('tnt.framework.dump')
local lang_of = require('tnt.framework.lang')
local layout_of = require('tnt.framework.layout')
local migrations_of = require('tnt.framework.migrations')
local offline = require('tnt.framework.offline')
local pages_of = require('tnt.framework.pages')
local providers_of = require('tnt.framework.providers')
local services = require('tnt.framework.services')
local sessions = require('tnt.framework.session')
local spec_of = require('tnt.framework.spec')

--- Отказ без места вызова: текст уходит оператору в alerts.
local fail = require('tnt.must.fail').raise

local Module = {}

---@class TntFrameworkSpec
---@field name string Имя журнала и метка слоёв
---@field base string|nil Корень раскладки для соглашений; по умолчанию `.`
---@field prefix string|nil Имя модуля корня раскладки: для приложения внутри пакета, где путь именем модуля не будет
---@field dependencies string[]|nil Роли ядра, нужные раньше
---@field schema table|nil Схема `tnt.validate` для настроек роли
---@field config string|nil Каталог настроек: файлы `<имя>.lua` с функцией от окружения
---@field providers string|string[]|nil Провайдеры: список имён модулей по порядку либо каталог файлов
---@field migrations string|nil Каталог миграций: файлы `NNN_имя.lua` с шагом `function(box)` либо `{ step, slice }`
---@field seeders string|nil Каталог наполнителей: файлы `<имя>.lua` с функцией от контейнера либо `{ run, after, dev }`
---@field models TntModel[]|nil Модели приложения; по соглашению — файлы каталога `app/models`
---@field build (fun(app: TntDiContainer, config: TntKernelConfig))|nil Объявления контейнера сверх провайдеров
---@field middleware any[]|(fun(app: TntDiContainer): any[])|nil Слои HTTP: список или функция от контейнера
---@field layers table<string, function>|(fun(app: TntDiContainer): table)|nil Свои слои реестра: фабрики по именам
---@field groups table<string, any[]>|(fun(app: TntDiContainer): table)|nil Группы реестра; `web` — после слоя сессий
---@field routes TntKernelRoutes|TntKernelRoutes[]|nil Маршруты HTTP: модуль или список модулей
---@field iproto TntKernelIproto|TntKernelIproto[]|nil Функции для lua_call: модуль или список модулей
---@field ready TntKernelReady|nil Действие по box.status сверх провайдеров
---@field view_data (fun(app: TntDiContainer): TntRouterViewData|nil)|nil Общие данные страниц сверх токена формы
---@field health_check (fun(app: TntDiContainer, cfg: any): boolean, string|nil)|nil Проверка готовности
---@field downtime string|TntDowntimeOptions|false|nil Режим обслуживания: файл, настройки либо false
---@field views string|false|nil Каталог шаблонов страниц (`tnt-template`) либо false — без страниц
---@field lang string|false|nil Каталог переводов (`tnt-i18n`), файл на язык, либо false — без переводов
---@field public public string|TntFrameworkAssetsOptions|false|nil Каталог для браузера: манифест сборки для `asset`
---@field views_compiled string|nil Каталог переведённых заранее страниц (`bootstrap/cache/views`)
---@field config_cache string|nil Собранные заранее настройки (`bootstrap/cache/config.lua`): окружение не читается
---@field cache TntCacheOptions|false|nil Кэш (`tnt-cache`): настройки либо false; раздел `cache` главнее
---@field throttle TntThrottleOptions|false|nil Ограничитель частоты (`tnt-throttle`): настройки либо false
---@field files TntFilesOptions|false|nil Диски (`tnt-files`): настройки либо false; раздел `files` главнее по диску
---@field session TntFrameworkSessionSpec|false|nil Сессии (`tnt-session`): настройки и хранилище либо false
---@field cors TntFrameworkCorsSpec|false|nil Межсайтовые запросы: слой `cors` и `path` либо false

--- Имя режима обслуживания в контейнере.
Module.DOWNTIME = 'downtime'

--- Имя движка страниц в контейнере.
Module.VIEW = 'view'

--- Имена служб по разделам настроек в контейнере: объявлены там, где
--- службы собираются, — второе место для тех же имён разошлось бы с ним.
Module.CACHE = services.CACHE
Module.THROTTLE = services.THROTTLE
Module.REDIS = services.REDIS
Module.DB = services.DB
Module.MAIL = services.MAIL
Module.FILES = services.FILES

--- Имя менеджера сессий в контейнере — оно же имя его слоя в реестре —
--- и группа слоёв страниц, в которой этот слой стоит.
Module.SESSION = sessions.NAME
Module.WEB = sessions.WEB

--- Имя помощника путей к собранным файлам — он же директива страницы.
Module.ASSET = 'asset'

--- Имя переводчика в контейнере.
Module.I18N = 'i18n'

--- Имя слоя языка запроса на входе роутера.
Module.LOCALE = 'locale'

--- Имя слоя межсайтовых запросов на входе роутера.
Module.CORS = cors_of.NAME

--- Шаги миграций каталога по номерам версий — для проверок, поднимающих
--- схему приложения на своём узле.
Module.migrations = migrations_of.of

--- Общие данные страниц: встроенные фреймворком, поверх — приложения.
---
--- Данные приложения главнее встроенных: странице, которой нужно своё
--- значение под тем же именем, его даёт одно объявление, а не каждый
--- обработчик. Данные обработчика главнее обоих — их кладёт роутер.
--- Приложение зовётся первым: его отказ парой и не таблица уходят роутеру
--- как есть — он отвечает на пару отказом, а на не таблицу бросает тем же
--- словом, что и без встроенных данных, — и токен сессии, заведённый
--- до такого ответа, заводился бы зря.
---
--- Не функцию от запроса складывать не с чем, и она уходит ядру как
--- есть: сложенная со встроенными, она дошла бы до роутера функцией
--- и бросила бы только на первой странице, а так отказывает сборка —
--- словом ядра, тем же, что у приложения без фреймворка.
---@param builtin TntRouterViewData|nil Встроенные данные: новая таблица на каждый вызов
---@param own any То, что отдала функция `view_data` приложения
---@return any view_data Функция от запроса, пусто либо не функция — ядру на отказ
local function page_data(builtin, own)
    if builtin == nil or type(own) ~= 'function' then
        return own or builtin
    end

    return function(request)
        local shared, err = own(request)

        if type(shared) ~= 'table' then
            return shared, err
        end

        -- Встроенные данные отдают таблицу всегда, пустую — без сессии.
        local merged = builtin(request) --[[@as table]]

        for name, value in pairs(shared) do
            merged[name] = value
        end

        return merged
    end
end

--- Заводит роль приложения: объявление из каталогов и списков — ядру.
---@param spec TntFrameworkSpec
---@return TntFrameworkRole
function Module.new(spec)
    spec_of.checked(spec)

    local base = spec.base or '.'
    local prefix = spec.prefix
    local layout

    spec, layout = layout_of.by_convention(spec)

    -- Каталоги, чьи файлы подключаются модулями, знают своё имя: у
    -- раскладки внутри пакета путь именем модуля не будет.
    local inside = function(name)
        return prefix ~= nil and (prefix .. '.' .. name) or nil
    end

    local providers = spec.providers ~= nil and providers_of.of(spec.providers, inside('bootstrap')) or {}

    -- Маршруты провайдера без сервера в зависимостях остались бы
    -- без HTTP на каждом узле — так же молча, как и маршруты приложения.
    local served = false

    for _, role in ipairs(spec.dependencies or {}) do
        if role == kernel.HTTPD then
            served = true
        end
    end

    for _, provider in ipairs(providers) do
        if provider.routes ~= nil and not served then
            fail(
                ('приложение: маршруты провайдера %s требуют roles.httpd в dependencies'):format(
                    provider.name
                )
            )
        end
    end

    -- Ядру уходит всё объявление, кроме провайдеров: их здесь
    -- разбирают на build, ready, routes и iproto. Незнакомого поля тут
    -- уже нет: его отверг `tnt.framework.spec`.
    ---@type any
    local declared = {}

    for key, value in pairs(spec) do
        declared[key] = value
    end

    declared.providers = nil
    declared.downtime = nil
    declared.views = nil
    declared.lang = nil
    declared.public = nil
    declared.views_compiled = nil
    declared.config_cache = nil
    declared.cache = nil
    declared.throttle = nil
    declared.files = nil
    declared.session = nil
    declared.cors = nil
    declared.seeders = nil

    if spec.config ~= nil then
        declared.config = config_of.sections_of(config_of.files(spec.config, inside('config')))
    end

    if spec.config_cache ~= nil then
        declared.config = config_of.cached(spec.config_cache)
    end

    -- Каталог, уже отданный ядру, второй раз не читается: реестр шагов
    -- у tnt.schema один на процесс.
    declared.migrations = nil

    if spec.migrations ~= nil then
        declared.migrations = migrations_of.once(spec.migrations)
    end

    --- Объявления фреймворка и приложения — на узле и вне его.
    ---
    --- Режим обслуживания и страницы — первыми: провайдеры вправе
    --- на них положиться (свои директивы страниц заводит провайдер).
    --- Провайдеры по порядку, потом `build`: у сборки последнее слово —
    --- она вправе подменить объявленное провайдером через replace.
    ---@param app TntDiContainer
    ---@param config table Место узла и разделы настроек приложения, как у ядра
    ---@param compiled string|nil Каталог переведённых заранее страниц
    ---@param on_node boolean На узле ли сборка: вне узла кэш не заводится
    local function assemble(app, config, compiled, on_node)
        local mode = downtime_of.of(spec.downtime, config.app)

        if mode ~= nil then
            app:value(Module.DOWNTIME, mode)
        end

        if type(spec.views) == 'string' then
            -- Движок свой на применение: перечитывание конфигурации
            -- подхватывает и правку страниц.
            local view = template.new({ path = spec.views, compiled = compiled })

            -- Канонический адрес — у всякого движка страниц, до провайдеров:
            -- рамка сайта вправе на него рассчитывать, а адрес ему даёт
            -- роутер приложения от `http.url`.
            view:markup(canonical.NAME, canonical.link)

            -- Показ значения — тоже у всякого движка и тоже до провайдеров:
            -- их страницы вправе на него рассчитывать, а имя `dump` не
            -- должно достаться директиве провайдера с другим смыслом.
            view:directive(dump.NAME, dump.show)
            app:value(Module.VIEW, view)
        end

        local assets = asset_of.of(spec.public, config.app)

        if assets ~= nil then
            app:value(Module.ASSET, assets)

            -- Директива страницы: в шаблоне стоит имя из исходников,
            -- браузеру уходит имя с отпечатком. Заводится здесь же, до
            -- провайдеров: их страницы вправе на неё рассчитывать.
            if app:has(Module.VIEW) then
                app:get(Module.VIEW):directive(Module.ASSET, assets)
            end
        end

        local translator = lang_of.of(spec.lang, config.app)

        if translator ~= nil then
            app:value(Module.I18N, translator)

            -- Директивы — до провайдеров, как и `@asset`: их страницы
            -- вправе на них рассчитывать.
            if app:has(Module.VIEW) then
                lang_of.directives(app:get(Module.VIEW), function()
                    return app:get(Module.I18N)
                end)
            end
        end

        -- Вне узла служб нет: драйверу кэша space нужен поднятый box,
        -- почта настраивает процесс, а провайдеру для объявлений они ни
        -- к чему — сборщики берут их лениво.
        if on_node then
            services.declare(app, config, spec)
            sessions.declare(app, config, spec.session)
        end

        for _, provider in ipairs(providers) do
            if provider.register ~= nil then
                provider.register(app, config)
            end
        end

        if spec.build ~= nil then
            spec.build(app, config)
        end
    end

    declared.build = function(app, config)
        assemble(app, config, spec.views_compiled, true)
    end

    ---@class TntFrameworkRole: TntKernelRole
    ---@field layout fun(): table<string, string|string[]> Что взято по соглашению о раскладке, а не объявлено явно
    ---@field offline_view fun(): TntTemplateEngine|nil Движок страниц приложения, собранного вне узла
    ---@field seed fun(opts: table|nil): (table|string|nil, string|nil) Наполнение базы наполнителями каталога
    ---@field migrations fun(opts: table|nil): (table|string|nil, string|nil) Состояние схемы узла
    local role

    local readies = {}
    local routes = {}

    -- Команды узла — первыми, до провайдеров и приложения: имя их
    -- функции занято фреймворком, и объявивший его провайдер получит
    -- отказ «объявлена дважды», а не тихую подмену. Роль заводится ниже,
    -- а модуль iproto зовётся на применении — поэтому роль приходит
    -- функцией.
    local iproto = {
        commands_of.iproto(spec.name, function()
            return role
        end),
    }

    for _, provider in ipairs(providers) do
        if provider.ready ~= nil then
            table.insert(readies, { name = 'провайдер ' .. provider.name, ready = provider.ready })
        end

        table.insert(routes, provider.routes)
        table.insert(iproto, provider.iproto)
    end

    if spec.ready ~= nil then
        table.insert(readies, { name = 'готовность приложения', ready = spec.ready })
    end

    -- Модуль приложения либо их список — в хвост, после провайдеров.
    for _, key in ipairs({ 'routes', 'iproto' }) do
        local own = key == 'routes' and routes or iproto

        ---@type any
        local declared_modules = spec[key]

        if type(declared_modules) == 'function' then
            declared_modules = { declared_modules }
        end

        for _, declare in ipairs(declared_modules or {}) do
            table.insert(own, declare)
        end
    end

    -- Слои входа приложения — до поиска маршрута, сверху вниз.
    declared.entry = function(app)
        -- Межсайтовые заголовки — выше всех: на предварительный `OPTIONS`
        -- к существующему пути роутер ответил бы сам, без разрешений,
        -- а 503 закрытого приложения без разрешения сценарий чужой
        -- страницы увидел бы сетевой ошибкой, а не словом и сроком.
        local layers = cors_of.entries(spec.cors, app:get('config').app)

        -- Режим обслуживания: закрытое приложение отвечает 503 и на путь,
        -- которого нет, и ни один его слой ниже до запроса не допускается.
        if app:has(Module.DOWNTIME) then
            table.insert(layers, { app:get(Module.DOWNTIME):layer(), name = Module.DOWNTIME })
        end

        -- Язык запроса — тоже на входе, до поиска маршрута: слои приложения
        -- и обработчик любого пути говорят уже на языке запроса.
        if app:has(Module.I18N) then
            table.insert(layers, { app:get(Module.I18N):layer(), name = Module.LOCALE })
        end

        return layers
    end

    -- Слой сессий — в реестр слоёв приложения и в группу `web`: маршрут
    -- страницы берёт группу именем, и место слоя в цепочке одно у всех.
    -- Свои слои и группы приложения ложатся туда же, а его группа `web` —
    -- после слоя сессий.
    declared.layers = function(app)
        return sessions.layers(app, spec.layers)
    end

    declared.groups = function(app)
        return sessions.groups(app, spec.groups)
    end

    -- Движок страниц — роутеру, ради `route.view('about', …)`.
    declared.view = function(app)
        if app:has(Module.VIEW) then
            return app:get(Module.VIEW)
        end

        return nil
    end

    -- Общие данные страниц — роутеру: токен формы при сессиях, поверх —
    -- данные приложения. Собираются после провайдеров и `build`, как
    -- и слои: менеджер, подменённый ими, и даёт токен.
    declared.view_data = function(app)
        return page_data(sessions.view_data(app), spec.view_data ~= nil and spec.view_data(app) or nil)
    end

    -- Страницы отказов — каталогу отказов ядра: `resources/views/errors`
    -- по тому же соглашению, что и остальные страницы. Каталог читается
    -- здесь, на сборке, а не на каждом промахе по адресу.
    declared.error_page = function(app)
        if app:has(Module.VIEW) then
            return pages_of.of(app:get(Module.VIEW))
        end

        return nil
    end

    -- Слово отказа — на языке запроса: строки `errors.*` каталога `lang/`
    -- по коду отказа. Без переводов слово остаётся словом отказа.
    declared.error_translate = function(app)
        if app:has(Module.I18N) then
            return lang_of.refusals(function()
                return app:get(Module.I18N)
            end)
        end

        return nil
    end

    declared.ready = readies
    declared.iproto = iproto

    -- Маршруты — только если они есть: пустой список ядро сочло бы
    -- заявкой на HTTP и потребовало бы roles.httpd в зависимостях.
    declared.routes = routes[1] ~= nil and routes or nil

    role = kernel.new(declared) --[[@as TntFrameworkRole]]

    database.attach(role, spec.name, spec.seeders, spec.migrations)

    role.layout = function()
        return layout
    end

    -- Переведённое заранее ложится туда, где его возьмёт движок на старте:
    -- в `views_compiled` либо по соглашению — даже если каталога ещё нет,
    -- ведь его и заводит первая сборка.
    local views_compiled = spec.views_compiled or layout_of.place(base, layout_of.VIEWS_COMPILED)

    --- Движок страниц приложения, собранного вне узла, — для перевода
    --- заранее (`bootstrap.views`): директивы, которые заводят провайдеры
    --- и `build`, в нём уже есть. Пусто — страниц у приложения нет.
    ---@return TntTemplateEngine|nil
    role.offline_view = function()
        local container = offline.assembled(spec.name, declared.config, function(app, config)
            assemble(app, config, views_compiled, false)
        end)

        local view = container:has(Module.VIEW) and container:get(Module.VIEW) or nil

        container:close()

        return view
    end

    return role
end

return Module
