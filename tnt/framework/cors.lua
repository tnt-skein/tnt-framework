--- Межсайтовые запросы приложения: слой `cors` на входе роутера.
---
---     cors = { origins = { 'https://app.example.org' }, methods = { 'PUT', 'DELETE' }, path = '/api' }
---
--- Слой стоит на входе, до поиска маршрута, а не среди слоёв приложения:
--- на `OPTIONS` к существующему пути роутер отвечает сам — 204 с `Allow`
--- и без разрешений, — и слой вокруг обработчика найденного маршрута
--- предварительного запроса не увидел бы. Браузер тогда отверг бы всякий
--- запрос сложнее простого.
---
--- Настройки — те же, что у слоя (`tnt.middleware.layer.cors`), и сверх
--- них начало пути фильтра `path`. Раздел `app.cors` настроек главнее
--- объявления по полю: источники у стенда и боя свои, и задаёт их
--- окружение без правки кода, а способы и заголовки API пишутся
--- объявлением рядом с ним. `false` в объявлении либо в разделе выключает
--- слой; без объявления и без раздела слоя нет — разрешение читать ответы
--- чужим страницам выдают только по просьбе.

local cors = require('tnt.middleware.layer.cors')

--- Отказ без места вызова: текст уходит оператору в alerts.
local fail = require('tnt.must.fail').raise

--- Проверки по имени без броска: текст отказа общий со всеми пакетами.
local explain = require('tnt.must').explain

local Module = {}

--- Имя слоя на входе роутера.
Module.NAME = 'cors'

--- Поля объявления и раздела: настройки слоя и начало пути фильтра.
---
--- Значения описаны как любые (`'?'`): их вид проверяет сам слой при
--- сборке, и второе правило здесь однажды разошлось бы с ним.
local FIELDS = {
    origins = '?',
    methods = '?',
    headers = '?',
    expose = '?',
    max_age = '?',
    credentials = '?',
    path = '?',
}

---@class TntFrameworkCorsSpec Слой межсайтовых запросов: настройки `tnt.middleware.layer.cors` и фильтр по пути
---@field origins string[]|nil Разрешённые источники; их вправе дать и раздел `app.cors`
---@field methods string[]|nil Способы сверх GET, HEAD и POST
---@field headers string[]|nil Заголовки запроса сверх тех, что браузер шлёт без спроса
---@field expose string[]|nil Заголовки ответа, видные сценарию
---@field max_age integer|nil Сколько секунд браузер помнит ответ на предварительный запрос
---@field credentials boolean|nil Пускать ли с куками и `Authorization`; по умолчанию нет
---@field path string|nil Начало пути: `/api` — сам путь и всё под ним; по умолчанию — все пути

--- Бросает отказ о незнакомом поле, если оно есть.
---
--- Поля сверяются здесь, а не слоем: `path` слою не настройка,
--- и отказ слоя назвал бы его незнакомым, а свою `tag` — знакомой.
---@param value table Объявление либо раздел
---@param what string Как назвать его в отказе
local function known(value, what)
    local stray = explain.options(value, what, FIELDS)

    if stray ~= nil then
        fail(stray)
    end
end

--- Проверяет поля объявления.
---
--- Зовётся при загрузке роли: источники вправе прийти разделом, и слой
--- целиком собирается только при применении, но опечатка в имени поля
--- видна уже здесь — `orgins` иначе дошло бы до слоя незнакомым ключом
--- только на первом применении.
---@param declared table
function Module.checked(declared)
    known(declared, 'приложение: cors')
end

--- Записи входа роутера: слой по объявлению и разделу `app` либо ничего.
---
--- Список, а не запись или пусто: на него ложатся остальные слои входа
--- приложения, и слой межсайтовых запросов в нём всегда первый.
---
--- Слой собирается при сборке роутера, то есть на каждом применении:
--- правка раздела подхватывается `config:reload()`, а негодные
--- настройки — отказ применения со словом слоя, видный оператору
--- в alerts. Слой собирается под `pcall`, чтобы его отказ ушёл без места
--- в исходнике: место здесь указало бы на строку фреймворка, а чинить
--- надо настройку.
---@param declared table|false|nil Объявление `cors`
---@param section any Раздел `app` настроек
---@return table[]
function Module.entries(declared, section)
    -- Не `and … or`: раздел со значением `false` дал бы так пусто,
    -- и выключить слой разделом было бы нельзя. Сравнение с nil,
    -- а не проверка на истину: `null` из YAML приходит `box.NULL`, он
    -- истинен, и слияние ниже споткнулось бы о него, как о таблицу.
    ---@type any
    local own = nil

    if type(section) == 'table' and section.cors ~= nil then
        own = section.cors
    end

    if declared == false or own == false or (declared == nil and own == nil) then
        return {}
    end

    if own ~= nil then
        if type(own) ~= 'table' then
            fail(
                ('приложение: app.cors должно быть table или false, получено %s'):format(
                    type(own)
                )
            )
        end

        known(own, 'приложение: раздел app.cors')
    end

    -- Источники вправе прийти только разделом, и до сборки слоя это ещё
    -- не его настройки: их вид проверит он сам.
    ---@type any
    local options = {}

    for _, source in ipairs({ declared or {}, own or {} }) do
        for key, value in pairs(source) do
            options[key] = value
        end
    end

    local path = options.path

    options.path = nil

    local ok, layer = pcall(cors.new, options)

    if not ok then
        fail(tostring(layer))
    end

    return { { layer, name = Module.NAME, path = path } }
end

return Module
