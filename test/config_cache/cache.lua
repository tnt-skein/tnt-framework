--- Раздел cache: приставка из окружения.
---@param env TntEnv
return function(env)
    return { prefix = env('TEST_CACHE_PREFIX') }
end
