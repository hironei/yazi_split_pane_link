--- @since 26.5.6

local messages = {
	title = "Pane link",
	wrong_tab_count =
		"リンク作成には2つのタブが必要です。split-tabsを有効にしてください。",
	missing_target = "アクティブペインにリンク対象がありません。",
	multiple_selection = "アクティブペインの選択ファイルは1つにしてください。",
	tab_unavailable = "リンク先のタブを取得できませんでした。",
	selected_unavailable = "リンク対象を取得できませんでした。",
	remote_target = "ローカルファイルシステムの項目だけリンクできます。",
	archive_target = "アーカイブ内の項目はリンクできません。",
	name_unavailable = "リンク対象の名前を取得できませんでした。",
	directory_unavailable = "リンク先ディレクトリを取得できませんでした。",
	orphan = "壊れたシンボリックリンクはリンクできません。",
	special_file = "通常ファイルまたはフォルダだけリンクできます。",
	inspect_failed = "リンク対象を確認できませんでした: ",
	process_unavailable = "リンク作成プロセスを開始できませんでした。",
	launch_failed = "リンク作成を起動できませんでした: ",
	wait_failed = "リンク作成の実行状態を取得できませんでした: ",
	process_failed = "リンクを作成できませんでした: 終了コード ",
	created = "リンクを作成しました: ",
}

local function notify(level, content)
	ya.notify {
		title = messages.title,
		content = content,
		timeout = level == "error" and 7 or 5,
		level = level,
	}
end

local function count_selected(selected)
	local count = 0

	for _ in pairs(selected or {}) do
		count = count + 1
	end

	return count
end

local function get_single_selected(selected)
	for _, url in pairs(selected or {}) do
		return url
	end

	return nil
end

local function validate_url(url)
	if not url then
		return nil, messages.selected_unavailable
	end

	if url.domain and tostring(url.domain) ~= "" then
		return nil, messages.remote_target
	end

	if url.is_archive then
		return nil, messages.archive_target
	end

	if not url.name or tostring(url.name) == "" then
		return nil, messages.name_unavailable
	end

	return url, nil
end

local function validate_hovered(hovered)
	if not hovered then
		return nil, messages.missing_target
	end

	local url, url_error = validate_url(hovered.url)
	if not url then
		return nil, url_error
	end

	local cha = hovered.cha
	if cha then
		if cha.is_orphan then
			return nil, messages.orphan
		end

		if cha.is_block or cha.is_char or cha.is_fifo or cha.is_sock then
			return nil, messages.special_file
		end
	end

	return url, nil
end

local function get_source_from_tab(tab)
	local selected_count = count_selected(tab.selected)

	if selected_count > 1 then
		return nil, messages.multiple_selection
	end

	if selected_count == 1 then
		return validate_url(get_single_selected(tab.selected))
	end

	return validate_hovered(tab.current and tab.current.hovered)
end

local get_link_targets = ya.sync(function()
	if #cx.tabs ~= 2 then
		return nil, nil, messages.wrong_tab_count
	end

	local active_index = cx.tabs.idx
	local other_index = active_index == 1 and 2 or 1
	local active_tab = cx.tabs[active_index]
	local other_tab = cx.tabs[other_index]

	if not active_tab or not other_tab then
		return nil, nil, messages.tab_unavailable
	end

	local source_url, source_error = get_source_from_tab(active_tab)
	if not source_url then
		return nil, nil, source_error
	end

	local cwd = other_tab.current and other_tab.current.cwd
	if not cwd then
		return nil, nil, messages.directory_unavailable
	end

	local destination_url = cwd:join(source_url.name)
	if not destination_url then
		return nil, nil, messages.directory_unavailable
	end

	return tostring(source_url), tostring(destination_url), nil
end)

local function inspect_source(source)
	local cha, err = fs.cha(Url(source), true)
	if not cha then
		return nil, messages.inspect_failed .. tostring(err)
	end

	if cha.is_orphan then
		return nil, messages.orphan
	end

	if cha.is_block or cha.is_char or cha.is_fifo or cha.is_sock then
		return nil, messages.special_file
	end

	return true, nil, cha.is_dir == true
end


local function launch_link(source, destination, is_dir, target_os)
	if target_os == "windows" then
		local args = { "/d", "/c", "mklink" }
		if is_dir then
			args[#args + 1] = "/J"
		end
		args[#args + 1] = destination
		args[#args + 1] = source

		return Command("cmd.exe")
			:arg(args)
			:spawn()
	end

	return Command("ln")
		:arg {
			"-s",
			source,
			destination,
		}
		:spawn()
end

local function monitor_link(child, destination)
	local ok, status, wait_error = pcall(function()
		return child:wait()
	end)

	if not ok then
		notify("error", messages.wait_failed .. tostring(status))
		return
	end

	if wait_error then
		notify("error", messages.wait_failed .. tostring(wait_error))
		return
	end

	if not status then
		notify("error", messages.wait_failed .. "状態が返されませんでした")
		return
	end

	if not status.success then
		notify("error", messages.process_failed .. tostring(status.code))
		return
	end

	ya.emit("refresh", {})
	notify("info", messages.created .. destination)
end

local function entry()
	local source, destination, target_error = get_link_targets()
	if target_error then
		notify("warn", target_error)
		return
	end

	local inspected, inspect_error, is_dir = inspect_source(source)
	if not inspected then
		notify("warn", inspect_error)
		return
	end

	-- Unix paths are passed as separate arguments. Windows uses cmd.exe only
	-- because mklink is a cmd builtin; the command name is fixed and paths are
	-- still passed as separate arguments.
	local ok, child, launch_error = pcall(launch_link, source, destination, is_dir, ya.target_os())
	if not ok then
		notify("error", messages.launch_failed .. tostring(child))
		return
	end

	if launch_error then
		notify("error", messages.launch_failed .. tostring(launch_error))
		return
	end

	if not child then
		notify("error", messages.process_unavailable)
		return
	end

	monitor_link(child, destination)
end

return {
	entry = entry,
}
