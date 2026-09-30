--- Настройки с обязательной переменной: без неё применение отказывает.
---@param env TntEnv
return function(env)
    return { password = env.required('TEST_MAIL_PASSWORD') }
end
