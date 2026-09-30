rockspec_format = '3.0'

package = 'tnt-framework'
version = 'scm-1'

source = {
    url = 'git+https://github.com/tnt-skein/tnt-framework.git',
    branch = 'main',
}

description = {
    summary = 'Раскладка приложения поверх ядра tnt-kernel: каталоги и списки',
    detailed = [[
        Приложение на Tarantool 3 — роль, и ядро tnt-kernel собирает её
        из объявления: функций и таблиц. Этот пакет берёт их из каталогов
        и списков приложения по соглашению, и называть каждый каталог
        отдельно не нужно: config/ — настройки из окружения по файлу
        на раздел, bootstrap/providers.lua — провайдеры по порядку,
        app/models — модели, database/migrations — шаги схемы по номерам
        версий, database/seeders — наполнители с зависимостями, routes/ —
        маршруты, слои и функции iproto, resources/views — страницы
        и страницы отказов браузеру, lang/ — переводы, public/ — файлы для
        браузера с путями по манифесту сборки. Что взято по соглашению,
        показывает role.layout(): умолчание не молчит.

        По разделам настроек пакет собирает службы в контейнер — клиент
        Redis, драйвер базы PostgreSQL либо MySQL, кэш, ограничитель
        частоты, почту, диски и сессии — и связывает их аргументами:
        кэшу и ограничителю на драйвере redis достаётся клиент приложения,
        один пул соединений на всех. Слой сессий стоит в группе web
        реестра слоёв, слой межсайтовых запросов cors — первым на входе
        роутера, выше режима обслуживания и языка запроса.

        Роль публикует функцию iproto <имя>_command: сценарий оператора
        зовёт через неё команды узла db:seed и migrate:status и кончается
        тем кодом выхода, которым команда кончилась на узле. Настройки
        и страницы собираются заранее, в bootstrap/cache, без подъёма
        узла. У страниц — директивы @canonical, @dump, @asset, @lang,
        @choice и @locale.

        Зависит от tnt-kernel (роль из объявления), tnt-di, tnt-config,
        tnt-env, tnt-template, tnt-i18n, tnt-error, tnt-schema, tnt-model,
        tnt-console, tnt-debug, tnt-downtime, tnt-middleware, tnt-session,
        tnt-cache, tnt-throttle, tnt-redis, tnt-postgres, tnt-mysql,
        tnt-mail, tnt-files, tnt-s3, tnt-log, tnt-clock, tnt-must
        и tnt-external. Покрытие строк и убитых мутантов — 100 %.
    ]],
    homepage = 'https://github.com/tnt-skein/tnt-framework',
    issues_url = 'https://github.com/tnt-skein/tnt-framework/issues',
    maintainer = 'tnt-skein',
    license = 'MIT',
    labels = { 'tarantool', 'framework', 'application', 'conventions', 'roles' },
}

dependencies = {
    'lua >= 5.1',
    'tnt-must',
    'tnt-cache',
    'tnt-clock',
    -- Вывод отчётов и команды узла: приложение командной строки,
    -- итог которого функция iproto отдаёт сценарию оператора.
    'tnt-console',
    'tnt-config',
    'tnt-di',
    -- Показ значения директивой страниц @dump.
    'tnt-debug',
    'tnt-downtime',
    'tnt-env',
    -- Смена учётки на время команды узла подменяется в проверках:
    -- в их процессе box не поднят.
    'tnt-external',
    -- Слово отказа на языке запроса: код отказа — ключ строки перевода.
    'tnt-error',
    'tnt-i18n',
    -- Роль из объявления: каталоги и списки пакет превращает в объявление
    -- ядра, а применяет роль ядро.
    'tnt-kernel',
    'tnt-log',
    'tnt-model',
    'tnt-schema',
    'tnt-template',
    -- Службы по разделам настроек. Клиент Redis, драйверы базы и почта
    -- грузятся, только когда раздел их назвал; рок pg или mysql под
    -- драйвером ставит приложение рецептом tnt-postgres и tnt-mysql.
    'tnt-mail',
    'tnt-mysql',
    'tnt-postgres',
    'tnt-redis',
    'tnt-throttle',
    -- Диски: локальный каталог и ведро; клиент S3 грузится, только когда
    -- раздел назвал диск s3 без своего клиента.
    'tnt-files',
    'tnt-s3',
    -- Сессии по разделу session: менеджер, его слой и группа web.
    'tnt-session',
    -- Межсайтовые запросы: готовый слой cors на входе роутера.
    'tnt-middleware',
}

build = {
    type = 'builtin',
    modules = {
        ['tnt.framework'] = 'tnt/framework.lua',
        ['tnt.framework.asset'] = 'tnt/framework/asset.lua',
        ['tnt.framework.bootstrap'] = 'tnt/framework/bootstrap.lua',
        ['tnt.framework.canonical'] = 'tnt/framework/canonical.lua',
        ['tnt.framework.commands'] = 'tnt/framework/commands.lua',
        ['tnt.framework.config'] = 'tnt/framework/config.lua',
        ['tnt.framework.cors'] = 'tnt/framework/cors.lua',
        ['tnt.framework.database'] = 'tnt/framework/database.lua',
        ['tnt.framework.downtime'] = 'tnt/framework/downtime.lua',
        ['tnt.framework.dump'] = 'tnt/framework/dump.lua',
        ['tnt.framework.files'] = 'tnt/framework/files.lua',
        ['tnt.framework.lang'] = 'tnt/framework/lang.lua',
        ['tnt.framework.layout'] = 'tnt/framework/layout.lua',
        ['tnt.framework.migrations'] = 'tnt/framework/migrations.lua',
        ['tnt.framework.models'] = 'tnt/framework/models.lua',
        ['tnt.framework.offline'] = 'tnt/framework/offline.lua',
        ['tnt.framework.pages'] = 'tnt/framework/pages.lua',
        ['tnt.framework.providers'] = 'tnt/framework/providers.lua',
        ['tnt.framework.seeders'] = 'tnt/framework/seeders.lua',
        ['tnt.framework.services'] = 'tnt/framework/services.lua',
        ['tnt.framework.session'] = 'tnt/framework/session.lua',
        ['tnt.framework.spec'] = 'tnt/framework/spec.lua',
    },
}
