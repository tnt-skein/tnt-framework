--- Тесты помощника путей к собранным файлам: манифест, память, правка.

local t = require('luatest')

local fio = require('fio')

local helper = dofile('test/helper.lua')
local testing = helper.testing

local g = t.group('tnt.framework.asset')

--- Ловушка журнала: предупреждения помощника видны только записью.
local journal = testing.capture_log()

--- Каталоги, заведённые проверкой: убираются после неё.
---@type string[]
local roots = {}

g.before_each(function()
    roots = {}
    g.asset = testing.load_sources(helper.MODULES, 'tnt.framework.asset')

    journal.forget()
end)

g.after_each(function()
    helper.unload()

    for _, root in ipairs(roots) do
        fio.rmtree(root)
    end
end)

--- Манифест сборки в новом каталоге `public`.
---@param text string|nil Содержимое манифеста; nil — манифеста нет вовсе
---@param build string|nil Каталог сборки внутри public; по умолчанию build
---@return string public Каталог public
---@return string manifest Путь к манифесту
local function public_with(text, build)
    local root = fio.tempdir()
    local directory = fio.pathjoin(root, build or 'build')

    table.insert(roots, root)
    fio.mktree(directory)

    local manifest = fio.pathjoin(directory, 'manifest.json')

    if text ~= nil then
        local handle = fio.open(manifest, { 'O_WRONLY', 'O_CREAT', 'O_TRUNC' }, tonumber('0644', 8))

        handle:write(text)
        handle:close()
    end

    return root, manifest
end

--- Манифест с одной записью.
local MANIFEST = '{"resources/css/app.scss": {"file": "assets/app-BX7Yy2Qk.css"}}'

g.test_name_from_the_sources_turns_into_a_name_with_a_fingerprint = function()
    local root = public_with(MANIFEST)
    local asset = g.asset.new({ path = root })

    t.assert_equals(asset('resources/css/app.scss'), '/build/assets/app-BX7Yy2Qk.css')
end

g.test_the_build_directory_can_be_named_otherwise = function()
    -- Имя каталога сборки входит и в адрес: раздача объявлена под ним же.
    local root = public_with(MANIFEST, 'dist')
    local asset = g.asset.new({ path = root, build = 'dist' })

    t.assert_equals(asset('resources/css/app.scss'), '/dist/assets/app-BX7Yy2Qk.css')
end

g.test_name_missing_from_the_manifest_goes_out_as_it_is = function()
    -- Уронить страницу из-за непрошедшей сборки нельзя: без стилей она
    -- некрасива, без страницы — недоступна.
    local root = public_with(MANIFEST)
    local asset = g.asset.new({ path = root })

    t.assert_equals(asset('resources/js/app.js'), '/resources/js/app.js')
    t.assert_equals(asset('/favicon.ico'), '/favicon.ico')
    t.assert_equals(journal.logged('в манифесте сборки нет «resources/js/app.js»'), true)
end

g.test_the_warning_about_one_name_is_written_once = function()
    -- Страница рисуется десять раз в секунду: запись на каждый вызов
    -- залила бы журнал.
    local root = public_with(MANIFEST)
    local asset = g.asset.new({ path = root })

    for _ = 1, 3 do
        asset('resources/js/app.js')
    end

    t.assert_equals(#journal.find_all('в манифесте сборки нет'), 1)
end

g.test_without_a_manifest_the_paths_go_out_as_they_are = function()
    local root = public_with(nil)
    local asset = g.asset.new({ path = root })

    t.assert_equals(asset('resources/css/app.scss'), '/resources/css/app.scss')
    t.assert_equals(#journal.find_all('манифеста сборки'), 1)

    -- Манифеста нет — предупреждение одно, сколько бы имён ни спросили.
    asset('resources/js/app.js')

    t.assert_equals(#journal.find_all('манифеста сборки'), 1)
end

g.test_a_broken_manifest_is_a_warning_and_not_a_fall = function()
    local root = public_with('{ "resources/css/app.scss": }')
    local asset = g.asset.new({ path = root })

    t.assert_equals(asset('resources/css/app.scss'), '/resources/css/app.scss')

    -- Причина лежит полем, а не в тексте: отказ разбора несёт кусок
    -- самого файла, а кусок с обрезанной кириллицей — уже не UTF-8,
    -- и журнал выбросил бы такое сообщение целиком.
    local record = journal.find('не разобран')

    t.assert_not_equals(record, nil)
    t.assert_str_contains(record.record.fields.reason, 'Expected value')
end

g.test_a_manifest_in_broken_bytes_does_not_spoil_the_record = function()
    -- Кусок файла в тексте отказа бывает не UTF-8: журнал вычищает
    -- поле, а сообщение остаётся читаемым.
    local root = public_with('{ это не json')
    local asset = g.asset.new({ path = root })

    t.assert_equals(asset('resources/css/app.scss'), '/resources/css/app.scss')

    local record = journal.find('не разобран')

    t.assert_str_contains(record.record.fields.reason, 'не UTF-8')
    t.assert_str_contains(record.record.message, 'манифест сборки')
end

g.test_a_manifest_that_is_not_an_object_is_a_warning_too = function()
    -- Разобрался, да не в то: число и строка — годный JSON, а записей
    -- в них нет, и спрашивать у них имя файла нечем.
    local root = public_with('42')
    local asset = g.asset.new({ path = root })

    t.assert_equals(asset('resources/css/app.scss'), '/resources/css/app.scss')
    t.assert_equals(journal.logged('не разобран'), true)
end

g.test_a_manifest_without_a_file_field_is_a_warning_too = function()
    -- Запись есть, а имени файла в ней нет: подставить нечего.
    local root = public_with('{"resources/css/app.scss": {"src": "app.scss"}}')
    local asset = g.asset.new({ path = root })

    t.assert_equals(asset('resources/css/app.scss'), '/resources/css/app.scss')
    t.assert_equals(journal.logged('в манифесте сборки нет'), true)
end

-- ── Память и перечитывание ───────────────────────────────────────────

--- Пишет манифест заново и сдвигает время правки.
---@param manifest string
---@param text string
---@param shift number Насколько сдвинуть время правки, секунды
local function rewritten(manifest, text, shift)
    local handle = fio.open(manifest, { 'O_WRONLY', 'O_CREAT', 'O_TRUNC' }, tonumber('0644', 8))

    handle:write(text)
    handle:close()

    -- На macOS время правки идёт целыми секундами, и обе записи
    -- проверки укладываются в одну: сдвиг делает правку видимой везде.
    local at = fio.lstat(manifest).mtime + shift

    fio.utime(manifest, at, at)
end

g.test_the_manifest_is_read_once_and_lives_in_memory = function()
    -- На боевом узле манифест меняется вместе с выкладкой, то есть
    -- с перезапуском процесса: читать его на каждую страницу незачем.
    local root, manifest = public_with(MANIFEST)
    local asset = g.asset.new({ path = root })

    t.assert_equals(asset('resources/css/app.scss'), '/build/assets/app-BX7Yy2Qk.css')

    rewritten(manifest, '{"resources/css/app.scss": {"file": "assets/app-NEW.css"}}', 10)

    t.assert_equals(asset('resources/css/app.scss'), '/build/assets/app-BX7Yy2Qk.css')
end

g.test_in_development_the_manifest_is_reread_when_it_changes = function()
    local root, manifest = public_with(MANIFEST)
    local asset = g.asset.new({ path = root, watch = true })

    t.assert_equals(asset('resources/css/app.scss'), '/build/assets/app-BX7Yy2Qk.css')

    rewritten(manifest, '{"resources/css/app.scss": {"file": "assets/app-NEW.css"}}', 10)

    t.assert_equals(asset('resources/css/app.scss'), '/build/assets/app-NEW.css')

    -- Время правки то же — файл не перечитывается: правка видна по нему,
    -- а не по каждому обращению к странице.
    local unchanged = fio.lstat(manifest).mtime

    rewritten(manifest, '{"resources/css/app.scss": {"file": "assets/app-THIRD.css"}}', 0)
    fio.utime(manifest, unchanged, unchanged)

    t.assert_equals(asset('resources/css/app.scss'), '/build/assets/app-NEW.css')
end

g.test_a_manifest_that_appeared_later_is_picked_up_in_development = function()
    -- Страницу открывают раньше, чем соберут стили: запомнить пустоту
    -- до перезапуска узла значило бы собирать стили впустую.
    local root, manifest = public_with(nil)
    local asset = g.asset.new({ path = root, watch = true })

    t.assert_equals(asset('resources/css/app.scss'), '/resources/css/app.scss')

    rewritten(manifest, MANIFEST, 0)

    t.assert_equals(asset('resources/css/app.scss'), '/build/assets/app-BX7Yy2Qk.css')
end

-- ── Объявление и раздел настроек ─────────────────────────────────────

g.test_the_helper_is_built_from_the_declaration = function()
    local root = public_with(MANIFEST)

    t.assert_equals(g.asset.of(root, nil)('resources/css/app.scss'), '/build/assets/app-BX7Yy2Qk.css')
    t.assert_equals(g.asset.of({ path = root }, nil)('resources/css/app.scss'), '/build/assets/app-BX7Yy2Qk.css')
end

g.test_without_a_public_directory_there_is_no_helper_at_all = function()
    -- Подставлять пути некуда, и молчаливый `asset`, отдающий что попало,
    -- хуже его отсутствия.
    t.assert_equals(g.asset.of(nil, nil), nil)
    t.assert_equals(g.asset.of(false, nil), nil)
    t.assert_equals(g.asset.of({}, nil), nil)
end

g.test_the_settings_section_has_the_last_word = function()
    local root = public_with(MANIFEST, 'dist')
    local asset = g.asset.of(root, { assets = { build = 'dist' } })

    t.assert_equals(asset('resources/css/app.scss'), '/dist/assets/app-BX7Yy2Qk.css')
end

g.test_watching_is_turned_on_and_off_by_the_section = function()
    local root, manifest = public_with(MANIFEST)
    local watching = g.asset.of(root, { assets = { watch = true } })

    t.assert_equals(watching('resources/css/app.scss'), '/build/assets/app-BX7Yy2Qk.css')

    rewritten(manifest, '{"resources/css/app.scss": {"file": "assets/app-NEW.css"}}', 10)

    t.assert_equals(watching('resources/css/app.scss'), '/build/assets/app-NEW.css')

    -- `watch = false` в разделе обязан выключать перечитывание,
    -- а не пропадать: иначе объявление с `watch = true` не отменить
    -- настройкой боевого узла.
    local fixed = g.asset.of({ path = root, watch = true }, { assets = { watch = false } })

    t.assert_equals(fixed('resources/css/app.scss'), '/build/assets/app-NEW.css')

    rewritten(manifest, '{"resources/css/app.scss": {"file": "assets/app-THIRD.css"}}', 20)

    t.assert_equals(fixed('resources/css/app.scss'), '/build/assets/app-NEW.css')
end

g.test_a_section_that_is_not_a_table_changes_nothing = function()
    local root = public_with(MANIFEST)
    local asset = g.asset.of(root, { assets = 'да' })

    t.assert_equals(asset('resources/css/app.scss'), '/build/assets/app-BX7Yy2Qk.css')
end
