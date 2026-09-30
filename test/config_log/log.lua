--- Настройки встроенного журнала из окружения: незаданное не трогается.
--- Карта модулей — таблицей, если задан уровень пула, иначе строкой.
---@param env TntEnv
return function(env)
    local modules = env('TEST_LOG_MODULES')

    if env.has('TEST_LOG_POOL') then
        modules = { ['tnt.pool'] = env('TEST_LOG_POOL') }
    end

    return { level = env('TEST_LOG_LEVEL'), format = env('TEST_LOG_FORMAT'), modules = modules }
end
