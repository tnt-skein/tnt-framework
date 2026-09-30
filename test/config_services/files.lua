--- Раздел files: локальный диск в каталоге из окружения и ведро, чей
--- клиент фреймворк собирает из полей диска.
---@param env TntEnv
return function(env)
    return {
        default = 'local',
        disks = {
            ['local'] = { driver = 'local', root = env('TEST_FILES_ROOT', '/tmp/tnt-files'), url = '/storage' },
            s3 = {
                driver = 's3',
                prefix = 'uploads/',
                url = 'https://cdn.example.org',
                endpoint = 'http://127.0.0.1:19000',
                bucket = 'tnt-live',
                access_key = 'ключ',
                secret_key = 'тайна',
                timeout = 2,
            },
        },
    }
end
