--- Маршруты образца: страница со своей директивой и страница, которая
--- показывает свои данные директивой фреймворка `@dump`.
return function(route)
    route.get('/about', function()
        return route.view('about', { started_at = 0 })
    end)

    -- Имя и город — кириллицей: показ не должен прятать их за `\xD0…`,
    -- а пароль — тайна под своим именем, и на странице его нет.
    route.get('/customer', function()
        return route.view('customer', {
            customer = { name = 'Иван <Петров>', city = 'Казань', password = 'hunter2' },
        })
    end)
end
