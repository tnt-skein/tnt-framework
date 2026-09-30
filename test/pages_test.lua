--- Тесты страниц отказов приложения: какой шаблон рисует какой код.

local t = require('luatest')

local fio = require('fio')

local helper = dofile('test/helper.lua')
local testing = helper.testing

local g = t.group('tnt.framework.pages')

--- Каталог страниц этой проверки: свой на каждую и убирается за ней.
---@type string
local directory

g.before_each(function()
    directory = fio.tempdir()
    g.pages = testing.load_sources(helper.MODULES, 'tnt.framework.pages')
    g.template = testing.module('tnt.template')
end)

g.after_each(function()
    fio.rmtree(directory)
    helper.unload()
end)

--- Движок страниц над каталогом с перечисленными шаблонами.
---@param files table<string, string> Имя шаблона с точками → разметка
---@return TntTemplateEngine
local function engine_with(files)
    for name, body in pairs(files) do
        local path = fio.pathjoin(directory, (name:gsub('%.', '/')) .. '.thtml.lua')

        fio.mktree(fio.dirname(path))
        testing.write_file(path, body)
    end

    return g.template.new({ path = directory })
end

--- Данные страницы, какими их отдаёт каталог отказов.
---@param status integer
---@return table
local function shown(status)
    return { status = status, title = 'Страницы нет', message = 'нет такого адреса' }
end

g.test_the_page_of_the_status_is_drawn_first = function()
    local draw = g.pages.of(engine_with({
        ['errors.404'] = '<h1>Страницы нет</h1>',
        ['errors.error'] = '<h1>{{ status }}</h1>',
    }))

    t.assert_equals(draw(shown(404)), '<h1>Страницы нет</h1>')
    -- На код без своего шаблона отвечает общая страница.
    t.assert_equals(draw(shown(503)), '<h1>503</h1>')
end

g.test_without_a_common_page_an_unknown_status_is_left_to_the_builtin_one = function()
    local draw = g.pages.of(engine_with({ ['errors.404'] = '<h1>Страницы нет</h1>' }))

    t.assert_equals(draw(shown(404)), '<h1>Страницы нет</h1>')
    -- Пусто — рисует встроенная страница пакета отказов: бросок здесь
    -- оставил бы отказ вовсе без ответа.
    t.assert_equals(draw(shown(500)), nil)
end

g.test_an_application_without_pages_of_refusal_draws_none = function()
    -- Каталог страниц есть, а страниц отказов в нём нет: приложение
    -- отвечает одним API, и рисует встроенная страница пакета отказов.
    local draw = g.pages.of(engine_with({ home = '<h1>Привет</h1>' }))

    t.assert_equals(draw(shown(404)), nil)

    -- Страниц нет вовсе: `views = false` у приложения, и спрашивать
    -- рисовальщика не о чем.
    t.assert_equals(g.pages.of(nil), nil)
end

g.test_the_page_sees_the_numbers_and_the_frame_of_the_site = function()
    -- Рамка сайта — обычное наследование шаблонов: страница отказа ничем
    -- не отличается от остальных, и номера приходят ей данными.
    local draw = g.pages.of(engine_with({
        ['layouts.app'] = '<body>@yield("content")</body>',
        ['errors.error'] = "@extends('layouts.app')\n@section('content')"
            .. '<h1>{{ title }}</h1><p>{{ incident }}</p>@endsection',
    }))

    t.assert_equals(
        draw({ status = 500, title = 'Что-то сломалось', incident = '4KJ7-QW9M' }),
        '<body><h1>Что-то сломалось</h1><p>4KJ7-QW9M</p></body>'
    )
end

return g
