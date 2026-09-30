# tnt-framework

Раскладка приложения на Tarantool 3: роль берётся из каталогов и списков
приложения — настройки из окружения, провайдеры, модели, миграции,
наполнители, маршруты, страницы, переводы, — а собирает и применяет её
ядро `tnt-kernel`. Разделы настроек становятся службами контейнера:
клиент Redis, драйвер базы, кэш, ограничитель частоты, почта, диски
и сессии.

```lua
-- bootstrap/app.lua — роль приложения; config.yaml подключает её: roles: [roles.httpd, bootstrap.app]
return require('tnt.framework').new({ name = 'demo', dependencies = { 'roles.httpd' } })
```

```lua
-- routes/web.lua — маршруты находятся сами, по каталогу routes/
return function(route, app)
    route.get('/about', function()
        return route.view('about', { instance = app:get('config').instance, started_at = 0 })
    end)
end
```

```
GET /about                      → <title>Главная</title> … <p>Узел demo-001, поднят 01.01.1970.</p>
GET /about  accept-language: en → <title>Home</title>, content-language: en
require('bootstrap.app').layout().routes   --> { 'routes.api', 'routes.web' }
```

Зависимости: [tnt-kernel](https://github.com/tnt-skein/tnt-kernel),
[tnt-di](https://github.com/tnt-skein/tnt-di),
[tnt-config](https://github.com/tnt-skein/tnt-config),
[tnt-env](https://github.com/tnt-skein/tnt-env),
[tnt-template](https://github.com/tnt-skein/tnt-template),
[tnt-i18n](https://github.com/tnt-skein/tnt-i18n),
[tnt-error](https://github.com/tnt-skein/tnt-error),
[tnt-schema](https://github.com/tnt-skein/tnt-schema),
[tnt-model](https://github.com/tnt-skein/tnt-model),
[tnt-console](https://github.com/tnt-skein/tnt-console),
[tnt-debug](https://github.com/tnt-skein/tnt-debug),
[tnt-downtime](https://github.com/tnt-skein/tnt-downtime),
[tnt-middleware](https://github.com/tnt-skein/tnt-middleware),
[tnt-session](https://github.com/tnt-skein/tnt-session),
[tnt-cache](https://github.com/tnt-skein/tnt-cache),
[tnt-throttle](https://github.com/tnt-skein/tnt-throttle),
[tnt-redis](https://github.com/tnt-skein/tnt-redis),
[tnt-postgres](https://github.com/tnt-skein/tnt-postgres),
[tnt-mysql](https://github.com/tnt-skein/tnt-mysql),
[tnt-mail](https://github.com/tnt-skein/tnt-mail),
[tnt-files](https://github.com/tnt-skein/tnt-files),
[tnt-s3](https://github.com/tnt-skein/tnt-s3),
[tnt-log](https://github.com/tnt-skein/tnt-log),
[tnt-clock](https://github.com/tnt-skein/tnt-clock),
[tnt-must](https://github.com/tnt-skein/tnt-must),
[tnt-external](https://github.com/tnt-skein/tnt-external).

## Зачем

Роль из объявления собрать можно и руками, но список маршрутов, шагов
схемы и сборщиков у каждого приложения один и тот же и растёт вместе
с ним. Пакет делает это один раз:

- **Одно место для каждой вещи.** Файл на своём месте подключается сам,
  а что взято по соглашению, показывает `role.layout()`.
- **Опечатка — при загрузке.** Провайдер с незнакомым полем, миграция
  без номера, наполнитель, ждущий несуществующего, — ошибка при загрузке
  модуля роли, а не на первом запросе.
- **Службы по настройкам, связь — аргументом.** Кэш и ограничитель
  на драйвере `redis` получают клиент приложения: один пул соединений
  на всех.
- **Команды узла с настоящим кодом выхода.** `db:seed` и `migrate:status`
  выполняет узел, а сценарий оператора кончается тем кодом, которым
  команда кончилась на узле.

## Установка

```sh
tt rocks install tnt-framework --server=https://tnt-skein.github.io/rocks
```

Или из исходников — зависимости и тогда ставятся с того же сервера:

```sh
git clone https://github.com/tnt-skein/tnt-framework.git
cd tnt-framework && tt rocks make --server=https://tnt-skein.github.io/rocks
```

Роки `pg` и `mysql` под драйверами базы — форки с починками; их ставит
приложение, которому нужна база SQL, рецептом `tnt-postgres` и `tnt-mysql`.

## Как пользоваться

| Что | Где |
|---|---|
| настройки из окружения, файл на раздел | `config/` |
| провайдеры по порядку | `bootstrap/providers.lua` |
| модели `tnt-model` | `app/models/` |
| шаги схемы `NNN_имя.lua` и наполнители | `database/migrations/`, `database/seeders/` |
| маршруты, слои, функции iproto | `routes/*.lua`, `routes/middleware.lua`, `routes/iproto.lua` |
| страницы и страницы отказов | `resources/views/`, `resources/views/errors/` |
| переводы, файл на язык | `lang/` |
| файлы для браузера и манифест сборки | `public/`, `public/build/manifest.json` |
| режим обслуживания | `storage/framework/down` |
| собранное заранее | `bootstrap/cache/` |

| Раздел настроек | Имя в контейнере |
|---|---|
| `config/redis.lua` | `redis` — клиент Redis |
| `config/database.lua` с `driver` | `db` — драйвер PostgreSQL либо MySQL |
| `config/cache.lua`, `config/throttle.lua` | `cache`, `throttle` |
| `config/mail.lua` | `mail` |
| `config/files.lua` | `files` — диски `local` и `s3` |
| `config/session.lua` | `session` — менеджер сессий, слой в группе `web`, токен формы в данных страниц |

Команды узла — сценарием оператора через функцию iproto `<имя>_command`:

```sh
$ tarantool console.lua db:seed --dev
наполнитель  записей
-----------  -------
statuses     4
customers    2
$ tarantool console.lua migrate:status --json | jq -r .steps[0].file
001_customers
```

## Проверки

```sh
make deps          # luatest, luacheck, luacov с cluacov, argparse и зависимости пакета в .rocks
make check         # форматирование, линт, проверки, покрытие с порогом 100 %
make test-large    # срез шага миграции на 300 000 строк: в make test пропускается
make mutants-all   # мутационное тестирование утилитой tnt-mutants из PATH, порог 100 % убитых
```

150 проверок, одна из них долгая и в `make check` пропускается; покрытие
строк — 100 % (1168 из 1168), убитых мутантов — 100 % (638 мутантов
в двадцати двух модулях).

## Документ

Полное описание с обоснованием решений: [docs/framework.md](docs/framework.md).

## Лицензия

MIT.
