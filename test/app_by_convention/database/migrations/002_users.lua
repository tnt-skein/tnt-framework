--- Второй шаг схемы: спейс пользователей — из объявления модели.
---
--- Модуль модели назван от пути этого файла: корень образца в наборе
--- и в отдельном репозитории пакета разный, а файл миграции читается
--- по пути, и своего имени модуля у него нет.
local chunk = debug.getinfo(1, 'S') --[[@as { source: string }]]
local root = chunk.source:match('^@(.+)/database/migrations/[^/]+$') --[[@as string]]

return require((root:gsub('/', '.')) .. '.app.models.user').migration()
