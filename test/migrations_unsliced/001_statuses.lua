--- Тот же долгий шаг без среза: срывается на срезе вызывающего.
---@param box table
return function(box)
    require('tnt.testing.clock').work_without_yielding(0.03)

    for _, row in box.space.probe:pairs() do
        box.space.probe:replace(row:update({ { '=', 'status', 'new' } }))
    end
end
