--- Раздел настроек по соглашению.
return function(env)
    return { word = env('TEST_GREETING', 'привет') }
end
