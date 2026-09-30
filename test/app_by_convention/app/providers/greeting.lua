--- Провайдер по соглашению.
return {
    register = function(app, config)
        app:value('greeting', config.greeting.word .. ', ' .. config.instance)
    end,
}
