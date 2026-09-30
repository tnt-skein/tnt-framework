--- Общие средства проверок раскладки приложения.
---
--- Фреймворк — обёртка над ядром: проверяется, что каталоги и списки
--- превращаются в правильное объявление, и проверяется это против
--- настоящего ядра, а мир вокруг роли подменяется той же внешней
--- зависимостью, что и у проверок ядра.
---
--- Исходники пакета читаются с диска, а не через `require`: у Tarantool
--- свой загрузчик `.rocks`, он идёт раньше `package.path` и подсунул бы
--- установленную копию пакета, если она есть. Проверки тогда шли бы
--- против вчерашнего кода, а покрытие считалось бы по нему.
---
--- Соседи — зависимости пакета и то, что берут они сами, — тоже грузятся
--- файлами, но из `.rocks`, куда их ставит `make deps`, и заново на каждую
--- проверку. Реестр шагов схемы, настройки журнала, каталог отказов
--- и подмены средств живут в их модулях, и оставленные соседней проверкой
--- они сделали бы порядок проверок частью их смысла. Проверяется этот
--- пакет, а не они: `.rocks` в покрытие не входит.
---
--- Оснастка в `test/testing/` — загрузчик исходников, файлы, часы,
--- ловушка журнала и узлы luatest — грузится так же и один раз
--- на процесс: второй экземпляр загрузчика не знал бы, что вытеснил
--- первый, и не вернул бы вытесненное на место.
---
--- Проверки берут всё через этот помощник, а не из оснастки напрямую:
--- помощник — единственное, чем файл проверок отличается от того же файла
--- там, где пакет живёт рядом со своими зависимостями. Поэтому и пути
--- к образцам проверки берут у него (`helper.path`, `helper.module_name`):
--- корень образцов там и здесь разный.

local fio = require('fio')
local socket = require('socket')
local t = require('luatest')

--- Модули оснастки в порядке зависимостей: узел берёт файлы и загрузчик,
--- ловушка журнала — загрузчик.
local TESTING = {
    { name = 'tnt.testing.sources', path = 'test/testing/sources.lua' },
    { name = 'tnt.testing.files', path = 'test/testing/files.lua' },
    { name = 'tnt.testing.clock', path = 'test/testing/clock.lua' },
    { name = 'tnt.testing.journal', path = 'test/testing/journal.lua' },
    { name = 'tnt.testing.node', path = 'test/testing/node.lua' },
}

for _, module in ipairs(TESTING) do
    if package.loaded[module.name] == nil then
        local chunk, failure = loadfile(fio.abspath(module.path))

        if chunk == nil then
            error(('оснастка %s не читается: %s'):format(module.name, tostring(failure)))
        end

        package.loaded[module.name] = chunk()
    end
end

local sources = package.loaded['tnt.testing.sources']
local files = package.loaded['tnt.testing.files']
local node = package.loaded['tnt.testing.node']

local helper = {}

--- Оснастка проверок под теми именами, что зовут проверки.
---
--- Только то, чем проверки пользуются: модуль той же загрузки и загрузка
--- исходников, ловушка журнала, чтение и запись файла и остановка узла.
helper.testing = {
    module = sources.module,
    load_sources = sources.load,
    capture_log = package.loaded['tnt.testing.journal'].capture,
    read_file = files.read,
    write_file = files.write,
    stop_node = node.stop,
}

--- Каталог проверок от корня репозитория: образцы лежат в нём.
local ROOT = 'test'

--- Путь к образцу проверок от корня репозитория.
---@param relative string Путь внутри каталога проверок
---@return string
function helper.path(relative)
    return ROOT .. '/' .. relative
end

--- Имя модуля образца проверок: путь каталога проверок с точками.
---
--- Образцы грузятся по имени, как их грузит узел приложения: корень
--- репозитория лежит на пути поиска модулей.
---@param relative string Имя внутри каталога проверок, через точки
---@return string
function helper.module_name(relative)
    return (ROOT:gsub('/', '.')) .. '.' .. relative
end

--- Корень репозитория: от него строятся пути узлов.
---
--- Считается от этого файла, а не от рабочего каталога: узел живёт
--- в своём временном каталоге, и относительный путь он не понял бы.
local this_file =
    assert(debug.getinfo(1), 'нет отладочной информации о файле').source:sub(2)
local project_root = fio.abspath(fio.pathjoin(fio.dirname(this_file), '..'))

--- Список модулей по именам: путь складывается из имени от приставки.
---@param prefix string Каталог с модулями: пусто — корень репозитория
---@param names string[] Имена модулей в порядке зависимостей
---@return { name: string, path: string }[]
local function listed(prefix, names)
    local list = {}

    for _, name in ipairs(names) do
        table.insert(list, { name = name, path = prefix .. name:gsub('%.', '/') .. '.lua' })
    end

    return list
end

--- Соседи в порядке зависимостей — из `.rocks`, куда их ставит `make deps`.
---
--- Первым идёт то, что берут, последним — то, что берёт: загруженный
--- позже модуль достался бы только тем, кто грузился после него. Ядро
--- с контейнером и раннером миграций — посередине: поверх него встают
--- режим обслуживания, страницы, кэш, настройки, переводы, ограничитель,
--- клиент Redis, драйверы базы, почта, диски, вывод команд и сессии.
--- Повторов нет: проверяльщика берут и ядро, и куки, а загруженный
--- второй раз модуль достался бы только тем, кто грузился после него.
local NEIGHBOURS = listed('.rocks/share/tarantool/', {
    'tnt.external',
    'tnt.log',
    'tnt.validate.text',
    'tnt.validate.rule',
    'tnt.validate.coerce',
    'tnt.validate.regex',
    'tnt.validate.rules',
    'tnt.validate.formats',
    'tnt.validate.check',
    'tnt.validate.settings',
    'tnt.validate',
    'tnt.must.fail',
    'tnt.must.types',
    'tnt.must.range',
    'tnt.must.text',
    'tnt.must.choice',
    'tnt.must.cdata',
    'tnt.must.spec',
    'tnt.must',
    'tnt.id.octets',
    'tnt.id.quote',
    'tnt.id.crockford',
    'tnt.error.secret',
    'tnt.error.failure',
    'tnt.error.hook',
    'tnt.error.incident',
    'tnt.error.catalog',
    'tnt.error.render',
    'tnt.error.accept',
    'tnt.error.options',
    'tnt.error.page',
    'tnt.error.translation',
    'tnt.error.web',
    'tnt.error',
    'tnt.validate.file',
    'tnt.hash.algorithm',
    'tnt.hash.encoding',
    'tnt.hash.compare',
    'tnt.hash.compute',
    'tnt.hash.stream',
    'tnt.hash.password',
    'tnt.hash',
    'tnt.fs.failure',
    'tnt.fs.system',
    'tnt.fs.writer',
    'tnt.fs.reader',
    'tnt.fs.file',
    'tnt.fs.tree',
    'tnt.fs.temp',
    'tnt.fs',
    'tnt.context.key',
    'tnt.context',
    'tnt.log.plain',
    'tnt.metrics.series.labels',
    'tnt.metrics.series.collector',
    'tnt.metrics.series',
    'tnt.router.neighbour',
    'tnt.router.options',
    'tnt.router.blame',
    'tnt.router.path',
    'tnt.router.constraints',
    'tnt.router.tree',
    'tnt.router.multipart',
    'tnt.router.upload',
    'tnt.router.form',
    'tnt.router.request',
    'tnt.router.response',
    'tnt.router.takeover',
    'tnt.router.errors',
    'tnt.router.signed',
    'tnt.router.address',
    'tnt.router.files.caching',
    'tnt.router.files.store',
    'tnt.router.files',
    'tnt.router.etag',
    'tnt.router.view',
    'tnt.router.pipeline',
    'tnt.router.declare',
    'tnt.router.series',
    'tnt.router.answer',
    'tnt.router',
    'tnt.id.entropy',
    'tnt.id.sequence',
    'tnt.id.uuid7',
    'tnt.id.ulid',
    'tnt.id',
    'tnt.clock',
    'tnt.middleware.fall',
    'tnt.middleware.blame',
    'tnt.middleware.chain',
    'tnt.middleware.filter',
    'tnt.middleware.layer.common',
    'tnt.middleware.layer.cors',
    'tnt.middleware.layer.log',
    'tnt.middleware.layer.timing',
    'tnt.middleware.layer.rescue',
    'tnt.middleware.layer.request_id',
    'tnt.middleware.layer.request_id_header',
    'tnt.middleware.registry',
    'tnt.middleware',
    'tnt.env.cast',
    'tnt.env.example',
    'tnt.env.parse',
    'tnt.env.secret',
    'tnt.env',
    'tnt.model.world',
    'tnt.model.failure',
    'tnt.model.stamp',
    'tnt.model.hook',
    'tnt.model.shape',
    'tnt.model.order',
    'tnt.model.check',
    'tnt.model.scope',
    'tnt.model.tuple',
    'tnt.model.topology',
    'tnt.model.migration',
    'tnt.model.query',
    'tnt.model.record',
    'tnt.model.factory',
    'tnt.model.entity',
    'tnt.model.gateway.local',
    'tnt.model.gateway.sharded',
    'tnt.model.gateway.remote',
    'tnt.model.gateway.forward',
    'tnt.model.serve',
    'tnt.model.binding',
    'tnt.model',
    'tnt.collection.value',
    'tnt.collection.guard',
    'tnt.collection.kind',
    'tnt.collection.path',
    'tnt.collection.order',
    'tnt.collection.sort',
    'tnt.collection.group',
    'tnt.collection.list',
    'tnt.collection.aggregate',
    'tnt.collection.merge',
    'tnt.collection.dict',
    'tnt.collection.chain',
    'tnt.collection',
    'tnt.storage.codes',
    'tnt.storage.failure',
    'tnt.storage.exact',
    'tnt.storage.value',
    'tnt.storage.within',
    'tnt.storage.link',
    'tnt.storage.statement',
    'tnt.storage.transaction',
    'tnt.storage.driver',
    'tnt.storage',
    'tnt.sql.kinds',
    'tnt.sql.dialect',
    'tnt.sql.names',
    'tnt.sql.context',
    'tnt.sql.raw',
    'tnt.sql.where',
    'tnt.sql.select',
    'tnt.sql.insert',
    'tnt.sql.change',
    'tnt.sql.table',
    'tnt.sql',
    'tnt.orm.world',
    'tnt.orm.columns',
    'tnt.orm.ddl',
    'tnt.orm.query',
    'tnt.orm.refusal',
    'tnt.orm.gateway',
    'tnt.orm',
    'tnt.trace.w3c',
    'tnt.trace.queue',
    'tnt.trace.span',
    'tnt.trace.hook',
    'tnt.trace.layer',
    'tnt.trace.message',
    'tnt.trace',
    'tnt.retry.attempt',
    'tnt.retry.backoff',
    'tnt.retry.classify',
    'tnt.retry.rule',
    'tnt.retry.budget',
    'tnt.retry.breaker',
    'tnt.retry.options',
    'tnt.retry.runner',
    'tnt.retry',
    'tnt.http.url',
    'tnt.http.body',
    'tnt.http.response',
    'tnt.http.failure',
    'tnt.http.policy',
    'tnt.http.settings',
    'tnt.http.transport',
    'tnt.http.stream',
    'tnt.http.hook',
    'tnt.http',
    'tnt.loop',
    'tnt.compress.system',
    'tnt.compress.zlib',
    'tnt.compress.failure',
    'tnt.compress.stream',
    'tnt.compress.deflater',
    'tnt.compress.inflater',
    'tnt.compress.layer',
    'tnt.compress',
    'tnt.trace.otlp.encode',
    'tnt.trace.otlp.reply',
    'tnt.trace.otlp.settings',
    'tnt.trace.otlp',
    'tnt.config.failure',
    'tnt.config.value',
    'tnt.config.reader',
    'tnt.config.writer',
    'tnt.config.settings',
    'tnt.config',
    'tnt.di',
    'tnt.schema',
    'tnt.kernel.world',
    'tnt.kernel.list',
    'tnt.kernel.http',
    'tnt.kernel.models',
    'tnt.kernel.tracing',
    'tnt.kernel.notifier',
    'tnt.kernel.spec',
    'tnt.kernel.signing',
    'tnt.kernel.settings',
    'tnt.kernel.journal',
    'tnt.kernel.schema',
    'tnt.kernel.iproto',
    'tnt.kernel',
    'tnt.cookie.octet',
    'tnt.cookie.date',
    'tnt.cookie.parse',
    'tnt.cookie.build',
    'tnt.cookie.sign',
    'tnt.cookie.suffix',
    'tnt.cookie.jar',
    'tnt.cookie',
    'tnt.downtime',
    'tnt.template.escape',
    'tnt.template.csrf',
    'tnt.template.sandbox',
    'tnt.template.sections',
    'tnt.template.directives',
    'tnt.template.translator',
    'tnt.template.source',
    'tnt.template.fragment',
    'tnt.template.stream',
    'tnt.template.engine',
    'tnt.template.warm',
    'tnt.template',
    'tnt.cache.series',
    'tnt.cache.record',
    'tnt.cache.lock',
    'tnt.cache.tagged',
    'tnt.cache.store',
    'tnt.cache.memory',
    'tnt.cache.redis',
    'tnt.cache.space',
    'tnt.cache',
    'tnt.str.chars',
    'tnt.str.guard',
    'tnt.str.json',
    'tnt.str.case',
    'tnt.str.edit',
    'tnt.str.cut',
    'tnt.str.checks',
    'tnt.str.russian',
    'tnt.str.convert',
    'tnt.str.encoding',
    'tnt.str.regex',
    'tnt.str.fluent',
    'tnt.str',
    'tnt.i18n.locale',
    'tnt.i18n.plural',
    'tnt.i18n.messages',
    'tnt.i18n.layer',
    'tnt.i18n.translator',
    'tnt.i18n',
    'tnt.throttle.limit',
    'tnt.throttle.memory',
    'tnt.throttle.redis',
    'tnt.throttle.layer',
    'tnt.throttle.limiter',
    'tnt.throttle',
    'tnt.pool.settings',
    'tnt.pool.opening',
    'tnt.pool.waiters',
    'tnt.pool',
    'tnt.tls.library',
    'tnt.tls.outcome',
    'tnt.tls.options',
    'tnt.tls.buffer',
    'tnt.tls.openssl',
    'tnt.tls.link',
    'tnt.tls',
    'tnt.redis.resp',
    'tnt.redis.link',
    'tnt.redis.settings',
    'tnt.redis',
    'tnt.postgres.settings',
    'tnt.postgres.rock',
    'tnt.postgres',
    'tnt.mysql.settings',
    'tnt.mysql.rock',
    'tnt.mysql',
    'tnt.mail.encode',
    'tnt.mail.message',
    'tnt.mail.parse',
    'tnt.mail.text',
    'tnt.mail.refusal',
    'tnt.mail.series',
    'tnt.mail.preview',
    'tnt.mail.letters',
    'tnt.mail.transport',
    'tnt.mail.smtp',
    'tnt.mail.pop3',
    'tnt.mail.imap',
    'tnt.mail',
    'tnt.date.explain',
    'tnt.date.moment',
    'tnt.date.arith',
    'tnt.date.http',
    'tnt.date.human',
    'tnt.date.iso',
    'tnt.date.mail',
    'tnt.date',
    'tnt.s3.xml',
    'tnt.s3.sign',
    'tnt.s3.reply',
    'tnt.s3.settings',
    'tnt.s3.call',
    'tnt.s3.download',
    'tnt.s3.upload',
    'tnt.s3.transfer',
    'tnt.s3',
    'tnt.files.failure',
    'tnt.files.settings',
    'tnt.files.reader',
    'tnt.files.writer',
    'tnt.files.driver.local',
    'tnt.files.driver.s3',
    'tnt.files.disk',
    'tnt.files',
    'tnt.debug.scalar',
    'tnt.debug.describe',
    'tnt.debug.measure',
    'tnt.debug.fibers',
    'tnt.debug',
    'tnt.process.failure',
    'tnt.process.system',
    'tnt.process.locate',
    'tnt.process.child',
    'tnt.process.run',
    'tnt.process',
    'tnt.console.system',
    'tnt.console.phrases',
    'tnt.console.declaration',
    'tnt.console.parser',
    'tnt.console.output',
    'tnt.console.app',
    'tnt.console.remote',
    'tnt.console',
    'tnt.session.state',
    'tnt.session.cache',
    'tnt.session.cookie',
    'tnt.session.refusal',
    'tnt.session.layer',
    'tnt.session.csrf',
    'tnt.session.manager',
    'tnt.session',
})

--- Модули, которые проверки фреймворка грузят: соседи, затем свои исходники.
helper.MODULES = sources.merge(
    NEIGHBOURS,
    listed('', {
        'tnt.framework.asset',
        'tnt.framework.canonical',
        'tnt.framework.dump',
        'tnt.framework.files',
        'tnt.framework.services',
        'tnt.framework.session',
        'tnt.framework.cors',
        'tnt.framework.spec',
        'tnt.framework.config',
        'tnt.framework.downtime',
        'tnt.framework.lang',
        'tnt.framework.models',
        'tnt.framework.layout',
        'tnt.framework.migrations',
        'tnt.framework.seeders',
        'tnt.framework.database',
        'tnt.framework.commands',
        'tnt.framework.pages',
        'tnt.framework.providers',
        'tnt.framework.offline',
        'tnt.framework.bootstrap',
        'tnt.framework',
    })
)

---@class TntKernelFakeServer
---@field options { handler: function } Обработчик всех запросов, как у рока
---@field original function Обработчик, с которым сервер был собран
---@field idle_timeout number|nil Срок простоя, который поставило ядро

--- Двойник сервера http.server: обработчик всех запросов в `options.handler`
--- и больше ничего.
---@return TntKernelFakeServer
function helper.fake_server()
    local function refusing()
        return { status = 404, body = 'сервер отвечает сам' }
    end

    local server = { options = { handler = refusing }, original = refusing, stopped = false, started = false }

    --- Подъём сервера: у своего порта его зовёт ядро, подняв сервер роком.
    function server:start()
        self.started = true
    end

    --- Закрытие сервера: его зовёт ядро у своего порта, а у чужого —
    --- не должно звать вовсе.
    function server:stop()
        self.stopped = true
    end

    return server
end

--- Двойник встроенного журнала: `cfg` — и вызов, и таблица настроек,
--- как у ядра. Что передали, копится в `applied`.
---@return table
local function fake_journal()
    local journal = { applied = {} }

    journal.cfg = setmetatable({ level = 'info', format = 'json', modules = { ['tnt.pool'] = 'warn' } }, {
        __call = function(current, opts)
            table.insert(journal.applied, opts)

            for key, value in pairs(opts) do
                current[key] = value
            end
        end,
    })

    return journal
end

---@class TntKernelFakeNotifier
---@field asked string[] Что ядро просило у уведомителя, по порядку
---@field publish_health_checks fun()
---@field withdraw_health_checks fun()

--- Двойник уведомителя: ровно то, чем пользуется ядро. Что просили,
--- копится в `asked` — `publish` и `withdraw`.
---@return TntKernelFakeNotifier
local function fake_notifier()
    local notifier = { asked = {} }

    function notifier.publish_health_checks()
        table.insert(notifier.asked, 'publish')
    end

    function notifier.withdraw_health_checks()
        table.insert(notifier.asked, 'withdraw')
    end

    return notifier
end

---@class TntKernelWorld
---@field roles string[] Роли инстанса
---@field server any Что `roles.httpd` отдаёт вместо сервера; пусто — сервера нет
---@field requested string|nil Имя сервера, которое у него просили
---@field hierarchy table Место узла
---@field is_router boolean
---@field is_storage boolean
---@field labels table|nil
---@field journal table|nil Двойник встроенного журнала: `cfg` зовётся и читается, как у ядра; пусто — настоящий
---@field bucket_count integer Число бакетов — моделям на хранилище
---@field instances table<string, table> Узлы кластера по имени — моделям для `remote`
---@field uris table<string, table> Адреса узлов под учёткой sharding — моделям для `remote`
---@field box table|nil Двойник `box` для моделей на узле с данными; пусто — настоящий
---@field net_box table|nil Двойник `net.box` для шлюза `remote`; пусто — настоящий
---@field notifier TntKernelFakeNotifier Двойник уведомителя: настоящий в проверках не трогается
---@field served { host: string, port: number }|nil Адрес, на котором роль подняла свой сервер

--- Мир вокруг роли: конфигурация ядра и роль сервера — двойниками.
---
--- Поля меняются проверкой на ходу: внешние зависимости читают их при каждом обращении,
--- и «сервер пропал при перечитывании» — это одно присваивание.
---@param overrides table|nil
---@return TntKernelWorld
function helper.world(overrides)
    local world = {
        roles = { 'roles.httpd', 'test.app' },
        server = helper.fake_server(),
        requested = nil,
        hierarchy = { group = 'routers', replicaset = 'router-001', instance = 'router-001-a' },
        is_router = true,
        is_storage = false,
        labels = { zone = 'a' },
        journal = fake_journal(),
        bucket_count = 100,
        instances = {},
        uris = {},
        notifier = fake_notifier(),
    }

    for key, value in pairs(overrides or {}) do
        world[key] = value
    end

    return world
end

--- Роли шардирования узла, как их отдаёт `config:get('sharding.roles')`.
---
--- Считаются от того же мира, что и `is_router`/`is_storage` ядра:
--- модели спрашивают у конфигурации роли, ядро — признаки, и в проверке
--- они обязаны говорить одно.
---@param world TntKernelWorld
---@return string[]
local function sharding_roles_of(world)
    local roles = {}

    if world.is_router then
        table.insert(roles, 'router')
    end

    if world.is_storage then
        table.insert(roles, 'storage')
    end

    return roles
end

--- Ставит внешние зависимости моделей на двойники того же мира.
---
--- Конфигурация у моделей своя, не ядра: они читают роли шардирования,
--- число бакетов и адреса соседей — того, что ядру не нужно. `box`
--- и `net.box` читаются из мира при каждом обращении: проверка ставит
--- двойника после загрузки, а без него идут настоящие.
---@param world TntKernelWorld
local function arm_models(world)
    sources.module('tnt.model')._set_source({
        config = function()
            return {
                get = function(_, path)
                    if path == 'sharding.roles' then
                        return sharding_roles_of(world)
                    end

                    assert(
                        path == 'sharding.bucket_count',
                        'модели спрашивают у конфигурации только шардирование'
                    )

                    return world.bucket_count
                end,
                info = function()
                    return { hierarchy = world.hierarchy }
                end,
                instances = function()
                    return world.instances
                end,
                instance_uri = function(_, _, opts)
                    return world.uris[opts.instance]
                end,
            }
        end,

        box = function()
            return world.box or rawget(_G, 'box')
        end,

        net_box = function()
            return world.net_box or require('net.box')
        end,
    })
end

--- Ставит внешние зависимости ядра на двойники мира.
---@param world TntKernelWorld
---@param kernel any Модуль ядра, загруженный исходниками
local function arm(world, kernel)
    -- Журнал подменяется, только если мир его завёл: без двойника
    -- проверка идёт в настоящий встроенный журнал процесса.
    local replacement = {
        config = function()
            return {
                info = function()
                    return { hierarchy = world.hierarchy }
                end,
                is_router = function()
                    return world.is_router
                end,
                is_storage = function()
                    return world.is_storage
                end,
                get = function(_, key)
                    assert(
                        key == 'labels',
                        'ядро спрашивает у конфигурации только labels'
                    )

                    return world.labels
                end,
            }
        end,

        httpd = function()
            return {
                -- Имя сервера ядро передаёт, и двойник обязан его принимать:
                -- средство, отличающееся от настоящего числом аргументов,
                -- в проверке ведёт себя не так, как в кластере.
                get_server = function(name)
                    world.requested = name

                    return world.server
                end,
            }
        end,

        -- Рок сервера: роль со своим портом поднимает его сама, и проверке
        -- надо видеть адрес, а не занимать настоящий порт.
        http_server = function()
            return {
                new = function(host, port)
                    world.served = { host = host, port = port }

                    return world.server
                end,
            }
        end,

        roles = function()
            return world.roles
        end,

        -- Уведомитель один на процесс, и его реестр проверок — тоже:
        -- настоящий, тронутый проверкой ядра, заводил бы проверки в реестре
        -- процесса проверок.
        notifier = function()
            return world.notifier
        end,
    }

    if world.journal ~= nil then
        replacement.journal = function()
            return world.journal
        end
    end

    kernel._set_source(replacement)
    arm_models(world)
end

--- Объявление приложения с нужными полями поверх минимального.
---@param overrides table|nil
---@return table
function helper.spec(overrides)
    local declared = { name = 'test.app' }

    for key, value in pairs(overrides or {}) do
        declared[key] = value
    end

    return declared
end

---@class TntKernelIncoming
---@field method string|nil Способ; по умолчанию GET
---@field path string Путь, как его прислал клиент, до раскодирования
---@field query string|nil Строка запроса
---@field body any Тело; таблица уходит JSON, строка — как есть
---@field headers table<string, string>|nil Заголовки, имена в нижнем регистре

--- Собирает запрос в том виде, в каком его отдаёт http.server.
---
--- Тело отдаётся так, как его отдаёт сервер: `Content-Length` по длине,
--- чтение не больше заявленного; что спросили, запоминается в `asked`.
---@param opts TntKernelIncoming
---@return table
function helper.incoming(opts)
    local headers = opts.headers or {}
    local text = opts.body

    if type(text) == 'table' then
        text = require('json').encode(text)
    end

    if text ~= nil then
        headers['content-length'] = tostring(#text)
    end

    local asked = {}

    return {
        method = opts.method or 'GET',
        path_raw = opts.path,
        path = opts.path,
        query = opts.query or '',
        headers = headers,
        asked = asked,
        read = function(_, size, timeout)
            table.insert(asked, { size = size, timeout = timeout })

            return text:sub(1, size)
        end,
    }
end

--- Глобалы, которые могли опубликовать роли ядра в проверках.
local KERNEL_GLOBALS = {
    'ping',
    'put',
    'storage_put',
    'later',
    'provider_order',
    'pages_about',
    'probe',
    'tnt_model_count',
    'tnt_model_delete',
    'tnt_model_find',
    'tnt_model_put',
    'tnt_model_select',
}

--- Функции команд узла, которые публикуют роли проверок: имя
--- приложения по умолчанию (`test.app`) и образца со страницами (`pages`).
helper.COMMANDS = { 'test_app_command', 'pages_command' }

--- Снимает функции команд узла, опубликованные ролями проверок.
local function forget_commands()
    for _, name in ipairs(helper.COMMANDS) do
        rawset(_G, name, nil)
    end
end

--- Снимает глобалы, опубликованные ролями проверок: свежая роль
--- следующей проверки публикует те же имена, и прежние заняли бы их.
function helper.forget_globals()
    for _, name in ipairs(KERNEL_GLOBALS) do
        rawset(_G, name, nil)
    end

    forget_commands()
end

--- Простая строка ответа Redis.
---@param text string
---@return string
local function status(text)
    return '+' .. text .. '\r\n'
end

--- Ошибка ответа Redis.
---@param text string
---@return string
local function refusal(text)
    return '-' .. text .. '\r\n'
end

--- Ответы двойнику Redis байтами.
helper.redis_reply = { status = status, error = refusal }

--- Разбирает команду, которую прислал драйвер: массив строк байтов.
---@param peer any Сокет двойника
---@return string[]|nil
local function command_of(peer)
    -- Не длиннее 64 байт: строка команды RESP всегда короче, а чужой
    -- протокол (приветствие TLS) без CRLF иначе ждал бы продолжения вечно.
    local head = peer:read({ delimiter = '\r\n', chunk = 64 })

    if head == nil or head == '' then
        return nil
    end

    local args = {}

    for _ = 1, tonumber(head:match('^%*(%d+)')) do
        local size = tonumber(peer:read({ delimiter = '\r\n' }):match('^%$(%d+)')) --[[@as integer]]

        table.insert(args, peer:read({ chunk = size + 2 }):sub(1, size))
    end

    return args
end

---@class TntRedisFakeAnswer
---@field reply string|nil Что отдать байтами
---@field delay number|nil Сколько помолчать перед ответом
---@field close boolean|nil Закрыть ли соединение после ответа

---@class TntRedisFake
---@field port integer Порт на петле
---@field commands string[][] Команды, которые дошли, по порядку
---@field connections integer Сколько соединений открыто всего
---@field finished integer Сколько соединений кончилось: клиент закрыл либо двойник
---@field peers table[] Сокеты двойника по соединениям
---@field stop fun() Погасить сервер и закрыть соединения

--- Двойник сервера Redis.
---
--- `respond(args, number)` получает команду и номер соединения и отвечает
--- байтами либо таблицей `{ reply, delay, close }`; пустой ответ —
--- молчание. Команды входа (`AUTH`, `SELECT`, `PING`) по умолчанию
--- отвечают сами, пока `respond` не ответит на них иначе.
---@param respond fun(args: string[], number: integer): string|TntRedisFakeAnswer|nil
---@return TntRedisFake
function helper.redis_server(respond)
    -- Порт и остановка появятся, когда сервер поднимется.
    ---@diagnostic disable-next-line: missing-fields
    local fake = { commands = {}, connections = 0, finished = 0, peers = {} } ---@type TntRedisFake

    local server = socket.tcp_server('127.0.0.1', 0, function(peer)
        fake.connections = fake.connections + 1
        table.insert(fake.peers, peer)

        local number = fake.connections

        while true do
            -- Под pcall: сокет двойника закрывают и снаружи (`stop`),
            -- и чтение из закрытого бросает — это конец разговора.
            local read, args = pcall(command_of, peer)

            if not read or args == nil then
                break
            end

            table.insert(fake.commands, args)

            local answer = respond(args, number)

            if answer == nil and (args[1] == 'AUTH' or args[1] == 'SELECT') then
                answer = status('OK')
            elseif answer == nil and args[1] == 'PING' then
                answer = status('PONG')
            end

            if type(answer) ~= 'table' then
                answer = { reply = answer }
            end

            if answer.delay ~= nil then
                require('fiber').sleep(answer.delay)
            end

            if answer.reply ~= nil then
                pcall(peer.write, peer, answer.reply)
            end

            if answer.close then
                break
            end
        end

        pcall(peer.close, peer)
        fake.finished = fake.finished + 1
    end)

    fake.port = server:name().port --[[@as integer]]

    fake.stop = function()
        server:close()

        for _, peer in ipairs(fake.peers) do
            pcall(peer.close, peer)
        end
    end

    return fake
end

--- Загружает исходники ядра и фреймворка, внешние зависимости ядра — на двойники мира.
---
--- Новая роль снимает функции команд узла, опубликованные прежней. На узле
--- роль приложения одна, и вторая с тем же именем получила бы отказ
--- «глобал занят» по делу; в проверке же роли с одним именем заводятся
--- по одной на случай, и прежняя до конца проверки не останавливается.
--- Вызов хвостовой: бросок `new` показывает на строку проверки, а не сюда.
---@param world TntKernelWorld
---@return any framework
function helper.load(world)
    local framework = sources.load(helper.MODULES, 'tnt.framework')
    local new = framework.new

    framework.new = function(spec)
        forget_commands()

        return new(spec)
    end

    -- Внешние зависимости ставятся на тот экземпляр ядра, который взял фреймворк.
    arm(world, sources.module('tnt.kernel'))

    return framework
end

--- Модули моделей образца: модель помнит `tnt.model`, с которым её
--- завели, и после перезагрузки исходников числилась бы чужой таблицей.
helper.MODEL_MODULES = {
    helper.module_name('app_by_convention.app.models.user'),
    helper.module_name('models_odd.plain'),
}

--- Модули приложений-образцов, которые заводят роль при загрузке: роль
--- помнит фреймворк, с которым её завели, и после перезагрузки исходников
--- собиралась бы прежним.
helper.ROLE_MODULES = {
    helper.module_name('app_with_pages.bootstrap.app'),
    helper.module_name('app_not_a_role.bootstrap.app'),
}

--- Убирает исходники, модели и роли образцов: следующая проверка грузит
--- их заново.
function helper.unload()
    sources.unload(helper.MODULES)

    for _, list in ipairs({ helper.MODEL_MODULES, helper.ROLE_MODULES }) do
        for _, name in ipairs(list) do
            package.loaded[name] = nil
        end
    end
end

--- Чтение окружения и то, что оно берёт, — из `.rocks`.
local ENV = listed('.rocks/share/tarantool/', {
    'tnt.external',
    'tnt.must.fail',
    'tnt.must.types',
    'tnt.must.range',
    'tnt.must.text',
    'tnt.must.choice',
    'tnt.must.cdata',
    'tnt.must.spec',
    'tnt.must',
    'tnt.env.cast',
    'tnt.env.example',
    'tnt.env.parse',
    'tnt.env.secret',
    'tnt.env',
})

--- Включены ли долгие проверки на настоящем объёме.
---
--- Переключатель читается тем же `tnt-env`, что и настройки приложений:
--- `1`, `yes`, `on` и `true` значат одно, а непонятное значение
--- останавливает прогон, а не выключает проверку молча. Чтение
--- собирается заново и убирается сразу: его берут при загрузке файла
--- проверки, и внешние зависимости с проверяльщиком, оставленные
--- в `package.loaded`, достались бы соседям, загрузившим свои раньше.
---@return boolean
function helper.large_tests()
    local enabled = sources.load(ENV, 'tnt.env').bool('TNT_LARGE_TESTS', false)

    sources.unload(ENV)

    return enabled
end

--- Что узел проверок среза берёт исходниками: загрузчик и работу без
--- уступки оснастки — ими пользуются подготовка схемы и шаги образцов —
--- и всё, что берёт фреймворк.
local ON_NODE = sources.merge({
    { name = 'tnt.testing.sources', path = 'test/testing/sources.lua' },
    { name = 'tnt.testing.clock', path = 'test/testing/clock.lua' },
}, helper.MODULES)

--- Узел для проверок среза шага из каталога миграций.
---@param memory integer Арена, байты
---@return table server
function helper.start_node(memory)
    return node.start({ modules = ON_NODE, box_cfg = { memtx_memory = memory } })
end

--- Путь поиска модулей узла: корень репозитория раньше `.rocks`.
---
--- Роль приложения ядро Tarantool загружает само, ещё при подъёме, поэтому
--- модули пакета и роль из каталога проверок узел находит путём поиска,
--- а не подстановкой в `package.loaded`: после подъёма подставлять поздно.
--- Зависимости — из `.rocks`.
---@return table env `LUA_PATH` и `LUA_CPATH`
local function search_paths()
    local rocks = fio.pathjoin(project_root, '.rocks')
    local paths = {
        fio.pathjoin(project_root, '?.lua'),
        fio.pathjoin(rocks, 'share', 'tarantool', '?.lua'),
        fio.pathjoin(rocks, 'share', 'tarantool', '?', 'init.lua'),
    }

    -- Сервер HTTP держит разбор запроса в собранной библиотеке, счётчик
    -- покрытия — тоже. Оба расширения: luarocks кладёт `.so`, а сборка
    -- cmake на macOS — `.dylib`.
    local libraries = {
        fio.pathjoin(rocks, 'lib', 'tarantool', '?.so'),
        fio.pathjoin(rocks, 'lib', 'tarantool', '?.dylib'),
    }

    return { LUA_PATH = table.concat(paths, ';') .. ';', LUA_CPATH = table.concat(libraries, ';') .. ';' }
end

--- Поднимает узел по декларативной конфигурации с ролью образца.
---
--- Узел — настоящее ядро Tarantool: роль оно загружает ещё при подъёме,
--- а миграции поднимает своим событием, и исходники узел находит путём
--- поиска от корня репозитория, а не подстановкой в `package.loaded`.
---
--- Сценарий у узла есть, хотя он пустой, и конфигурация приходит
--- окружением (`TT_CONFIG`), а не режимом luatest `config_file`. Узел
--- без сценария читает Lua из унаследованного stdin, и там, где труба
--- не закрыта, замирает целиком: подъём проходит, а на запросы узел
--- не отвечает, и luatest ждёт готовности до срока. Строгий режим
--- глобалов сценарий включает первой строкой: роль и обработчики, которые
--- проверка гоняет на узле, — тот же код, что в процессе проверок,
--- и опечатка в глобале там должна падать так же.
---
--- Каталог у узла свой, временный; останавливает узел и убирает каталог
--- `testing.stop_node`.
---@param name string Имя инстанса
---@param instance string[] Поля инстанса в строчной записи YAML
---@return table server
function helper.start_configured(name, instance)
    local workdir = fio.tempdir()
    local lines = {
        'credentials: {users: {guest: {roles: [super]}}}',
        'groups: {g: {replicasets: {r: {instances: {' .. name .. ': {',
        "  iproto: {listen: [{uri: 'unix/:./instance.iproto'}]},",
    }

    for _, line in ipairs(instance) do
        table.insert(lines, '  ' .. line .. ',')
    end

    table.insert(lines, '}}}}}}')

    files.write(fio.pathjoin(workdir, 'config.yaml'), table.concat(lines, '\n'))
    files.write(fio.pathjoin(workdir, 'init.lua'), "require('strict').on()\n_G.ready = true\n")

    local env = search_paths()

    env.TT_CONFIG = 'config.yaml'
    env.TT_INSTANCE_NAME = name

    local server = t.Server:new({
        alias = name,
        command = arg[-1],
        args = { 'init.lua' },
        chdir = workdir,
        net_box_uri = 'unix/:' .. fio.pathjoin(workdir, 'instance.iproto'),
        setsearchroot = false,
        env = env,
    })

    server:start({ wait_until_ready = true })

    return server
end

--- Готовит узел к подъёму схемы: чистая схема и запуск работы в своём
--- файбере с заданным срезом.
---
--- Спейсы раннера и probe прежней проверки убираются: узел один на набор,
--- а каждая проверка поднимает схему с нуля.
---@param server table
local function prepare(server)
    server:exec(function()
        for _, name in ipairs({ 'app_schema_meta', 'app_schema_steps', 'probe', 'probe_two' }) do
            if box.space[name] ~= nil then
                box.space[name]:drop()
            end
        end

        local fiber = require('fiber')

        -- Запускает работу в своём файбере с коротким срезом: срез ставится
        -- маленьким, чтобы не наполнять журнал на секунды счёта. Файбер
        -- свой и незащищённый, как у такта; брошенное отдаётся вызывающему.
        rawset(_G, 'with_slice', function(slice, work)
            local outcome

            local worker = fiber.new(function()
                ---@diagnostic disable-next-line: undefined-field
                fiber.self():set_max_slice(slice)
                fiber.yield()
                outcome = work()
            end)

            worker:set_joinable(true)

            local ok, failure = worker:join()
            assert(ok, failure)

            return outcome
        end)
    end)
end

--- Поднимает схему каталогом миграций под срезом вызывающего — тем же
--- путём, что узел приложения: шаги читает `framework.migrations`,
--- регистрирует ядро, поднимает `tnt.schema`.
---
--- Узел готовит `prepare`: чистая схема и запуск
--- работы в своём файбере с заданным срезом. Спейс probe — строки
--- `{ id, 'old' }`, которые шаги образцов переписывают в `'new'`.
---@param server table
---@param directory string Каталог образца
---@param rows integer Сколько строк в probe
---@param slice number Срез файбера вызывающего, секунды
---@return { err: string|nil, applied: integer[]|nil, version: integer, first: string|nil, last: string|nil }
function helper.raised_under_slice(server, directory, rows, slice)
    prepare(server)

    return server:exec(function(modules, path, count, limit)
        local fiber = require('fiber')

        -- Реестр шагов у tnt.schema один на процесс: свежий экземпляр
        -- на каждую проверку — вместе с ядром и каталогом, которые его
        -- взяли.
        local kernel_schema = require('tnt.testing.sources').load(modules, 'tnt.kernel.schema')
        local schema = require('tnt.schema')
        local catalog = require('tnt.framework.migrations')

        local space = box.schema.space.create('probe', {
            format = { { name = 'id', type = 'unsigned' }, { name = 'status', type = 'string' } },
        })
        space:create_index('pk', { parts = { { field = 'id', type = 'unsigned' } } })

        -- Кусками с уступкой: сотни тысяч строк одной транзакцией сами
        -- упёрлись бы в срез.
        for first = 1, count, 10000 do
            box.begin()

            for id = first, math.min(first + 9999, count) do
                space:insert({ id, 'old' })
            end

            box.commit()
            fiber.yield()
        end

        kernel_schema.registered(catalog.of(path))

        return _G.with_slice(limit, function()
            local report, err = schema.upgrade()
            local first, last = space:get(1), space:get(count)

            return {
                err = err,
                applied = report ~= nil and report.applied or nil,
                version = schema.current_version(),
                first = first ~= nil and first.status or nil,
                last = last ~= nil and last.status or nil,
            }
        end)
    end, { sources.absolute(ON_NODE), require('fio').abspath(directory), rows, slice })
end

return helper
