--- Функции iproto по соглашению: routes/iproto.lua.
return function(app)
    return {
        greeting = function()
            return app:get('greeting')
        end,
    }
end
