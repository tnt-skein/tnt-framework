--- Третий провайдер: только действие по готовности.
return {
    ready = function()
        table.insert(rawget(_G, 'provider_order'), '30_watcher.ready')
    end,
}
