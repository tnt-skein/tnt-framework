--- Раздел session: имя куки и срок из окружения, кука без Secure —
--- проверки ходят без TLS.
---
--- Драйвер и шифровальщик тоже из окружения, но пустые по умолчанию:
--- без драйвера сессии идут умолчанием `tnt-session`, а шифровальщик
--- в разделе — ровно та ошибка, которую сборка обязана назвать.
---@param env TntEnv
return function(env)
    return {
        driver = env('TEST_SESSION_DRIVER'),
        name = env('TEST_SESSION_NAME', 'demo_session'),
        lifetime = env('TEST_SESSION_LIFETIME', 600),
        cipher = env('TEST_SESSION_CIPHER'),
        cookie = { secure = false },
    }
end
