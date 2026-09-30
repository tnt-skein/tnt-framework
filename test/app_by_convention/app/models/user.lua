--- Модель по соглашению: файл `app/models/user.lua` возвращает модель.
local model = require('tnt.model')

return model.define({
    space = 'users',
    fields = {
        { 'id', 'unsigned', primary = true },
        model.bucket_of('id'),
        { 'name', 'string', min = 1, max = 255, trim = true },
    },
})
