--- Раздел cache: драйвер из окружения, клиента раздел не несёт.
---@param env TntEnv
return function(env)
    return { driver = env('TEST_CACHE_DRIVER', 'memory'), prefix = 'кэш:' }
end
