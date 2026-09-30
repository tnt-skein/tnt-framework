--- Провайдер страниц: директива, которую заводит само приложение.
return {
    register = function(app)
        -- @since(секунды_эпохи) — дата по UTC, чтобы проверка не зависела
        -- от пояса машины.
        app:get('view'):directive('since', function(at)
            return os.date('!%d.%m.%Y', at)
        end)
    end,
}
