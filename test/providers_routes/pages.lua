--- Провайдер со своими маршрутами и функциями iproto — как loadRoutesFrom.
local router = require('tnt.router')

return {
    register = function(app)
        app:value('pages', { about = 'о приложении' })
    end,

    routes = function(api, app)
        api.get('/pages/about', function()
            return router.text(app:get('pages').about)
        end)
    end,

    iproto = function(app)
        return {
            pages_about = function()
                return app:get('pages').about
            end,
        }
    end,
}
