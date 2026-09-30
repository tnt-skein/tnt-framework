--- Раздел redis: порт двойника сервера из окружения.
---@param env TntEnv
return function(env)
    return { port = env('TEST_REDIS_PORT', 6379), timeout = 1, retry = { attempts = 1 } }
end
