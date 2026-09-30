--- Провайдер для проверок: объявление и действие по готовности.
--- Приставка в имени задаёт порядок: этот идёт первым.
return {
    register = function(app, config)
        app:single('greeting', function()
            return 'привет, ' .. config.instance
        end)
        rawset(_G, 'provider_order', { '10_greeting.register' })
    end,

    ready = function(app, status, key)
        table.insert(rawget(_G, 'provider_order'), ('10_greeting.ready:%s:%s'):format(key, tostring(status.is_ro)))

        if status.fail_first then
            error('первый провайдер сорвался', 0)
        end

        app:get('greeting')
    end,
}
