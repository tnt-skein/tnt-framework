--- Проверки директивы `@dump`: показ значения из данных страницы.
---
--- Показ собирает `tnt-debug`, директиву заводит фреймворк у движка
--- страниц приложения, — и проверяется весь путь на образце
--- `app_with_pages`: маршрут, данные страницы, экранирование ответа.

local t = require('luatest')

local helper = dofile('test/helper.lua')
local testing = helper.testing

local g = t.group('tnt.framework.dump')

--- Корень образца: страница `customer` показывает свои данные.
local PAGES = helper.path('app_with_pages')

---@type TntKernelWorld
local world

---@type any
local framework

g.before_each(function()
    world = helper.world()
    framework = helper.load(world)
end)

g.after_each(function()
    helper.forget_globals()
    helper.unload()
end)

--- Роль образца, применённая на мире двойников; `build` — сверх провайдеров.
---@param build function|nil
---@return any role
local function applied(build)
    local role = framework.new(helper.spec({ dependencies = { 'roles.httpd' }, base = PAGES, build = build }))

    role.apply(nil)

    return role
end

--- Ответ приложения образца на путь.
---@param path string
---@return table
local function asked(path)
    return world.server.options.handler(world.server, helper.incoming({ path = path }))
end

g.test_every_value_is_shown_in_its_turn = function()
    local dump = testing.module('tnt.framework.dump')

    t.assert_equals(dump.NAME, 'dump')

    -- Без значений показывать нечего, а `nil` — значение: страницу
    -- смотрят ровно затем, чтобы увидеть пустоту.
    t.assert_equals(dump.show(), '')
    t.assert_equals(dump.show(nil), 'nil')

    -- Каждое значение — своим многострочным показом, через запятую
    -- с переводом строки; `nil` первым не обрывает счёт.
    t.assert_equals(dump.show(nil, 'два'), 'nil,\n"два"')
    t.assert_equals(dump.show({ id = 7, tags = { 'a' } }, 1), '{\n    id = 7,\n    tags = {\n        "a"\n    }\n},\n1')
end

g.test_the_page_of_the_sample_shows_its_data_with_the_secret_hidden = function()
    applied()

    local response = asked('/customer')

    t.assert_equals(response.status, 200, response.body)
    -- Кириллица — как есть, пароль — отметкой журнала, а угловые скобки
    -- и кавычки показа — экранированы: ответ директивы вывода проходит
    -- экранирование, и строка из данных разметкой не станет.
    t.assert_equals(
        response.body,
        table.concat({
            '<pre>{',
            '    city = &quot;Казань&quot;,',
            '    name = &quot;Иван &lt;Петров&gt;&quot;,',
            '    password = [скрыто]',
            '}</pre>',
            '',
        }, '\n')
    )
end

g.test_everything_in_the_brackets_is_a_value = function()
    local view = applied().container():get('view')

    -- Без значений — пусто; второе значение — значение, а не настройки
    -- показа.
    t.assert_equals(view:compile('<p>@dump()</p>')(), '<p></p>')
    t.assert_equals(
        view:compile('<pre>@dump(order, total)</pre>')({ order = { id = 7 }, total = 1.5 }),
        '<pre>{\n    id = 7\n},\n1.5</pre>'
    )
    t.assert_equals(
        view:compile('<pre>@dump(customer)</pre>')({ customer = { name = 'Иван', password = 'hunter2' } }),
        '<pre>{\n    name = &quot;Иван&quot;,\n    password = [скрыто]\n}</pre>'
    )
end

g.test_the_name_is_taken_before_the_providers_of_the_application = function()
    -- Директиву фреймворк заводит до провайдеров и `build`: своя
    -- директива с тем же именем — отказ сборки, а не тихая подмена
    -- показа, на который рассчитывают страницы приложения.
    t.assert_error_msg_equals(
        'приложение test.app не собрано: шаблоны: директива @dump уже есть',
        applied,
        function(app)
            app:get('view'):directive('dump', tostring)
        end
    )
end
