--- Шаг схемы: спейсы кэша app_cache и app_cache_tags.
return function(box)
    require('tnt.cache.space').migrate(box)
end
