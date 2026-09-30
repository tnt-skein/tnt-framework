--- Раздел throttle: драйвер из окружения, клиента раздел не несёт.
---@param env TntEnv
return function(env)
    return { driver = env('TEST_THROTTLE_DRIVER', 'memory'), prefix = 'предел:' }
end
