--- Раздел app с настройками режима обслуживания, как config/app.php.
---@param env TntEnv
return function(env)
    return {
        maintenance = {
            driver = env('TEST_MAINTENANCE_DRIVER', 'file'),
            path = env('TEST_MAINTENANCE_PATH'),
            except = { '/health' },
        },
    }
end
