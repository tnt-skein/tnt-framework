--- Наполнитель образца: находится по соглашению и зовётся с контейнером
--- применения — приветствие берётся из его настроек.
---@param app TntDiContainer
return function(app)
    rawset(_G, 'seeded_greeting', app:get('config').greeting.word)

    return 1
end
