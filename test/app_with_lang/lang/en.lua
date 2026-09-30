--- Строки образца по-английски.
return {
    home = { title = 'Home' },
    nodes = { '{count} node', '{count} nodes' },
    -- Слова отказов: по коду отказа, а у отказа без кода — по статусу.
    errors = {
        ['404'] = 'No such address',
        order = { unfit = 'The order did not fit' },
    },
}
