--- Настройки приложения для проверок: умолчания рядом с именем переменной.
---@param env TntEnv
return function(env)
    return {
        debug = env('TEST_APP_DEBUG', false),
        port = env('TEST_APP_PORT', 8080),
    }
end
