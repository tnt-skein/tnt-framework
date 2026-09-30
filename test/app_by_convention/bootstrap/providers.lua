--- Провайдеры по соглашению: список из bootstrap/providers.lua.
---
--- Имя провайдера — от имени этого модуля: корень образца в наборе
--- и в отдельном репозитории пакета разный, а модуль знает своё имя.
---@type string
local name = ...
local root = name:gsub('%.bootstrap%.providers$', '')

return { root .. '.app.providers.greeting' }
