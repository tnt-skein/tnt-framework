--- Первый шаг схемы для проверок: спейс клиентов.
---@param box table
return function(box)
    box.schema.space.create('customers', { format = { { name = 'id', type = 'unsigned' } } })
    box.space.customers:create_index('primary', { parts = { { field = 'id', type = 'unsigned' } } })
end
