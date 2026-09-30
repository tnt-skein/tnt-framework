--- Язык по умолчанию: переводов у образца два.
---@param env TntEnv
return function(env)
    return { locale = env('TEST_LOCALE', 'ru') }
end
