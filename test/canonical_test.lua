--- Проверки директивы `@canonical`: тег канонического адреса по адресу
--- из данных страницы.
---
--- Адрес собирает роутер приложения от `http.url`, тег пишет директива
--- у движка страниц, который заводит фреймворк, — и проверяется весь путь:
--- раздел `http` роли, маршрут, данные страницы и рамка.

local t = require('luatest')

local fio = require('fio')

local helper = dofile('test/helper.lua')
local testing = helper.testing

local g = t.group('tnt.framework.canonical')

--- Адрес приложения за обратным прокси.
local URL = 'https://shop.example.org'

---@type TntKernelWorld
local world

---@type any
local framework

--- Корень приложения этой проверки: свой на каждую и убирается за ней.
---@type string
local base

g.before_each(function()
    world = helper.world()
    framework = helper.load(world)
    base = fio.tempdir()
end)

g.after_each(function()
    fio.rmtree(base)
    helper.forget_globals()
    helper.unload()
end)

--- Кладёт страницу в каталог страниц приложения.
---@param name string Имя с точками: точка — каталог
---@param body string
local function page(name, body)
    local path = fio.pathjoin(base, 'resources', 'views', (name:gsub('%.', '/')) .. '.thtml.lua')

    fio.mktree(fio.dirname(path))
    testing.write_file(path, body)
end

--- Тело ответа приложения на путь со строкой запроса.
---@param address string
---@return string
local function asked(address)
    local path, query = address:match('^([^?]*)%??(.*)$')
    local response = world.server.options.handler(world.server, helper.incoming({ path = path, query = query }))

    t.assert_equals(response.status, 200, response.body)

    return response.body
end

g.test_the_link_is_written_only_for_an_address = function()
    local canonical = testing.module('tnt.framework.canonical')

    t.assert_equals(canonical.NAME, 'canonical')
    t.assert_equals(
        canonical.link(URL .. '/articles?page=2&sort=new'),
        '<link rel="canonical" href="https://shop.example.org/articles?page=2&amp;sort=new">'
    )

    -- Страница без адреса не получает ничего: пустой `href` поисковик
    -- прочёл бы адресом самой страницы — со всеми метками рассылки.
    t.assert_equals(canonical.link(nil), '')
    t.assert_equals(canonical.link(''), '')
    t.assert_equals(canonical.link(box.NULL), '')
end

g.test_an_address_of_the_wrong_kind_blames_the_line_of_the_page = function()
    page('about', '<head>\n@canonical(7)</head>')

    local role = framework.new(helper.spec({ base = base }))

    role.apply(nil)

    t.assert_error_msg_equals(
        'about:2: @canonical ждёт адрес строкой, а не number',
        role.container():get('view').render,
        role.container():get('view'),
        'about'
    )
end

g.test_the_page_gets_the_canonical_address_built_by_the_router_of_the_application = function()
    page('layouts.app', '<head>@canonical(canonical)</head>@yield("content")')
    page('article', "@extends('layouts.app')\n@section('content')<h1>{{ slug }}</h1>@endsection")

    local role = framework.new(helper.spec({
        base = base,
        dependencies = { 'roles.httpd' },
        routes = function(route)
            route.get('/articles/:slug', function(request)
                return route.view('article', {
                    slug = request.params.slug,
                    canonical = route.canonical(request, { query = { 'page' } }),
                })
            end)

            route.get('/drafts/:slug', function(request)
                return route.view('article', { slug = request.params.slug })
            end)
        end,
    }))

    role.apply({ http = { url = URL } })

    -- Метка рассылки отброшена, названное поле осталось; `&` в значении
    -- атрибута было бы `&amp;`.
    t.assert_equals(
        asked('/articles/%D0%BF?page=2&utm_source=mail'),
        '<head><link rel="canonical" href="https://shop.example.org/articles/%D0%BF?page=2"></head><h1>п</h1>'
    )

    -- Черновику адрес не положен — тега нет вовсе.
    t.assert_equals(asked('/drafts/x'), '<head></head><h1>x</h1>')
end
