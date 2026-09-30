--- Долгий шаг со срезом: переписывает каждую строку probe одной
--- транзакцией, без уступки, — как шаг, которому мала секунда ядра.
---
--- Сначала шаг работает без уступки дольше короткого среза быстрой
--- проверки: так её срыв без среза не зависит от скорости машины.
return {
    step = function(box)
        require('tnt.testing.clock').work_without_yielding(0.03)

        for _, row in box.space.probe:pairs() do
            box.space.probe:replace(row:update({ { '=', 'status', 'new' } }))
        end
    end,
    slice = 30,
}
