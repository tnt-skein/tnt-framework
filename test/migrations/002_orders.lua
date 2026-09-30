--- Второй шаг: спейс заказов.
---@param box table
return function(box)
    box.schema.space.create('orders', { format = { { name = 'id', type = 'unsigned' } } })
    box.space.orders:create_index('primary', { parts = { { field = 'id', type = 'unsigned' } } })
end
