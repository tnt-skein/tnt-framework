--- Страница образца: строки на языке запроса.
return function(route)
    route.get('/', function()
        return route.view('home', { count = 5 })
    end)

    -- Отказ обработчика по договору границы HTTP: его код — ключ строки
    -- перевода `errors.order.unfit`.
    route.get('/orders/:id', function()
        return nil, { status = 422, code = 'order.unfit', message = 'заказ отклонён' }
    end)
end
