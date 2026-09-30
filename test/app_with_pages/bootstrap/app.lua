--- Приложение со своей директивой страниц — для сборки страниц заранее
--- и для показа данных страницы директивой фреймворка `@dump`.
---
--- Как `bootstrap/app.lua` приложения: `bootstrap.views` грузит его
--- по имени модуля от корня и переводит страницы его движком. Корень —
--- от того же имени: в наборе и в отдельном репозитории пакета он разный.
---@type string
local name = ...
local base = name:gsub('%.bootstrap%.app$', ''):gsub('%.', '/')

return require('tnt.framework').new({
    name = 'pages',
    dependencies = { 'roles.httpd' },
    base = base,
})
