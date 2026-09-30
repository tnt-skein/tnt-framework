--- Раздел mail: отправитель и сервер отправки, шифрование из окружения.
---@param env TntEnv
return function(env)
    return {
        from = 'noreply@example.org',
        tls = env('TEST_MAIL_TLS', 'none'),
        smtp = { host = 'mail.example.org' },
    }
end
