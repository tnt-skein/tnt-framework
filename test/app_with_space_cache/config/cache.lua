--- Раздел cache: кэш приложения на спейсе, спейс заводит шаг миграции.
---@param env TntEnv
return function(env)
    return { driver = env('CACHE_DRIVER', 'space'), prefix = 'demo:' }
end
