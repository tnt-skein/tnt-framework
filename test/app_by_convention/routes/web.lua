--- Маршруты по соглашению: любой файл routes/, кроме middleware и iproto.
return function(route, app)
    route.get('/', function()
        return route.text(app:get('greeting'))
    end)

    route.get('/page', function()
        return route.view('greeting', { greeting = 'привет', who = '<мир>' })
    end)
end
