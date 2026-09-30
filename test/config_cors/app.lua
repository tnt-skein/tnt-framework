--- Раздел app с настройками слоя межсайтовых запросов из окружения —
--- тот же вид, что у примера в docs/framework.md.
---
--- Источники и путь пусты по умолчанию: без переменных раздел полей
--- не задаёт, и слой собирается по объявлению. `TEST_CORS=false`
--- выключает слой разделом — так его выключают на стенде без правки кода.
---@param env TntEnv
return function(env)
    return {
        cors = env.bool('TEST_CORS', true) and {
            origins = env.list('TEST_CORS_ORIGINS'),
            path = env('TEST_CORS_PATH'),
        } or false,
    }
end
