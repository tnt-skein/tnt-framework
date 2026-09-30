--- Раздел database: драйвер из окружения; без него — настройки хранения
--- самого Tarantool, и базы SQL нет.
---@param env TntEnv
return function(env)
    return {
        driver = env('TEST_DATABASE_DRIVER'),
        host = 'db',
        user = 'app',
        db = 'app',
    }
end
