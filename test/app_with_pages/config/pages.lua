--- Раздел настроек образца: сборка вне узла читает его, как на старте.
return function(env)
    return { title = env('TEST_PAGES_TITLE', 'О приложении') }
end
