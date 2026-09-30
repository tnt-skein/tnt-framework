--- Слои по соглашению: routes/middleware.lua.
return function(app)
    return {
        function(request, nxt)
            local response, err = nxt(request)

            if response == nil then
                return nil, err
            end

            response.headers['x-served-by'] = app:get('config').instance

            return response
        end,
    }
end
