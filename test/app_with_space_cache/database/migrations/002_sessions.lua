--- Шаг схемы: спейсы сессий app_sessions и app_sessions_tags.
return function(box)
    require('tnt.cache.space').migrate(box, 'app_sessions')
end
