--- Второй провайдер: только объявление, без действия по готовности.
return {
    register = function(app)
        table.insert(rawget(_G, 'provider_order'), '20_farewell.register')
        app:single('farewell', function(inner)
            return inner:get('greeting'):gsub('привет', 'пока')
        end)
    end,
}
