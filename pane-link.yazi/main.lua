--- @since 26.5.6

local messages = {
	title = "Pane link",
	wrong_tab_count =
		"Link creation requires exactly two tabs. Enable split-tabs.",
	missing_target = "No link target is available in the active pane.",
	multiple_selection = "Select exactly one item in the active pane.",
	tab_unavailable = "Could not access the other tab.",
	selected_unavailable = "Could not access the link target.",
	remote_target = "Only local filesystem items can be linked.",
	archive_target = "Items inside archives cannot be linked.",
	name_unavailable = "Could not determine the link target name.",
	directory_unavailable = "Could not determine the destination directory.",
	orphan = "Broken symbolic links cannot be linked.",
	special_file = "Only regular files and folders can be linked.",
	invalid_name = "The link name must be a single valid basename.",
	inspect_failed = "Could not inspect the link target: ",
	process_unavailable = "Could not start the link creation process.",
	sudo_unavailable = "File links require %USERPROFILE%\\scoop\\shims\\sudo.cmd: ",
	temp_dir_unavailable = "Could not determine the temporary directory (%TEMP%).",
	temp_script_failed = "Could not create the temporary link script: ",
	launch_failed = "Could not start link creation: ",
	wait_failed = "Could not determine the link creation status: ",
	process_failed = "Could not create the link: exit code ",
	created = "Link created: ",
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
		return nil, nil, nil, messages.wrong_tab_count
	end

	local active_index = cx.tabs.idx
	local other_index = active_index == 1 and 2 or 1
	local active_tab = cx.tabs[active_index]
	local other_tab = cx.tabs[other_index]

	if not active_tab or not other_tab then
		return nil, nil, nil, messages.tab_unavailable
	end

	local source_url, source_error = get_source_from_tab(active_tab)
	if not source_url then
		return nil, nil, nil, source_error
	end

	local cwd = other_tab.current and other_tab.current.cwd
	if not cwd then
		return nil, nil, nil, messages.directory_unavailable
	end

	local destination_dir = tostring(cwd)
	if destination_dir == "" then
		return nil, nil, nil, messages.directory_unavailable
	end

	return tostring(source_url), destination_dir, tostring(source_url.name), nil
end)

local get_active_tab_index = ya.sync(function()
	return cx.tabs.idx, #cx.tabs
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

local function get_sudo_path()
	local user_profile = os.getenv("USERPROFILE")
	if not user_profile or user_profile == "" then
		return nil, messages.sudo_unavailable .. "USERPROFILE is not set"
	end

	local sudo_path = user_profile:gsub("\\", "/") .. "/scoop/shims/sudo.cmd"
	local cha, err = fs.cha(Url(sudo_path), true)
	if not cha or cha.is_dir then
		return nil, messages.sudo_unavailable .. sudo_path .. (err and (" (" .. tostring(err) .. ")") or "")
	end

	return sudo_path, nil
end

-- Scoop's sudo.cmd elevates by re-joining its arguments into one string and
-- re-parsing that string across two nested PowerShell processes. That chain
-- has been observed to corrupt a plain "mklink dest source" argument list
-- (e.g. splitting "C:\Users\..." into a stray "/Users" switch for mklink).
-- Writing the mklink call to a temp script and passing only that single
-- path through sudo.cmd avoids the multi-hop re-parsing entirely, and lets
-- us suppress mklink's own console output at the source (mklink's success
-- message otherwise reaches Yazi's console via sudo.cmd's AttachConsole,
-- bypassing this plugin's own stdout/stderr redirection).
local function get_temp_script_path()
	local temp_dir = os.getenv("TEMP") or os.getenv("TMP")
	if not temp_dir or temp_dir == "" then
		return nil, messages.temp_dir_unavailable
	end

	local unique = string.format("%x%x%x", os.time(), math.floor(os.clock() * 1000), math.random(0, 0xffffff))
	return temp_dir:gsub("\\", "/") .. "/pane-link-" .. unique .. ".cmd", nil
end

local function write_link_script(path, destination, source)
	local file, err = io.open(path, "w")
	if not file then
		return nil, err
	end

	file:write('@echo off\r\n')
	file:write('mklink "' .. destination .. '" "' .. source .. '" >nul 2>&1\r\n')
	file:write('exit /b %errorlevel%\r\n')
	file:close()

	return true, nil
end

local function validate_link_name(name, target_os)
	if not name or name == "" then
		return nil, messages.invalid_name
	end

	if name == "." or name == ".." or name:find("[/\\\\]") or name:find("%c") then
		return nil, messages.invalid_name
	end

	if target_os == "windows" then
		if name:find('[<>:"|?*]') then
			return nil, messages.invalid_name
		end

		local last = name:sub(-1)
		if last == "." or last == " " then
			return nil, messages.invalid_name
		end
	end

	return name, nil
end

local function launch_link(source, destination, is_dir, target_os, sudo_path, script_path)
	if target_os == "windows" then
		if not is_dir then
			return Command("cmd.exe")
				:arg {
					"/d",
					"/c",
					sudo_path,
					"cmd.exe",
					"/d",
					"/c",
					script_path,
				}
				:stdout(Command.NULL)
				:stderr(Command.NULL)
				:spawn()
		end

		local args = { "/d", "/c", "mklink" }
		args[#args + 1] = "/J"
		args[#args + 1] = destination
		args[#args + 1] = source

		return Command("cmd.exe")
			:arg(args)
			:stdout(Command.NULL)
			:stderr(Command.NULL)
			:spawn()
	end

	return Command("ln")
		:arg {
			"-s",
			source,
			destination,
		}
		:stdout(Command.NULL)
		:stderr(Command.NULL)
		:spawn()
end

local function monitor_link(child, destination, script_path)
	local ok, status, wait_error = pcall(function()
		return child:wait()
	end)

	if script_path then
		os.remove(script_path)
	end

	if not ok then
		notify("error", messages.wait_failed .. tostring(status))
		return
	end

	if wait_error then
		notify("error", messages.wait_failed .. tostring(wait_error))
		return
	end

	if not status then
		notify("error", messages.wait_failed .. "no status was returned")
		return
	end

	if not status.success then
		notify("error", messages.process_failed .. tostring(status.code))
		return
	end

	ya.emit("refresh", {})

	-- "refresh"/"watch" only ever touch the active tab, so the destination
	-- pane (when it isn't active) never sees the new link. Round-tripping
	-- tab_switch is the only public way to reload another tab, since
	-- tab_switch itself runs "refresh" on the tab it switches into.
	local active_index, tab_count = get_active_tab_index()
	if tab_count == 2 then
		local other_index = active_index == 1 and 2 or 1
		ya.emit("tab_switch", { other_index - 1 })
		ya.emit("tab_switch", { active_index - 1 })
	end

	notify("info", messages.created .. destination)
end

local function entry()
	local source, destination_dir, source_name, target_error = get_link_targets()
	if target_error then
		notify("warn", target_error)
		return
	end

	local inspected, inspect_error, is_dir = inspect_source(source)
	if not inspected then
		notify("warn", inspect_error)
		return
	end

	local target_os = ya.target_os()
	local requested_name, input_event = ya.input {
		title = "Link name (leave empty for " .. source_name .. "):",
		pos = { "top-center", y = 3, w = 50 },
		value = "",
	}
	if input_event ~= 1 then
		return
	end

	local link_name = requested_name
	if not link_name or link_name == "" then
		link_name = source_name
	end

	local valid_name, name_error = validate_link_name(link_name, target_os)
	if not valid_name then
		notify("warn", name_error)
		return
	end

	local destination_url = Url(destination_dir):join(valid_name)
	if not destination_url then
		notify("warn", messages.directory_unavailable)
		return
	end
	local destination = tostring(destination_url)

	local sudo_path, script_path
	if target_os == "windows" and not is_dir then
		local sudo_error
		sudo_path, sudo_error = get_sudo_path()
		if not sudo_path then
			notify("error", sudo_error)
			return
		end

		local script_error
		script_path, script_error = get_temp_script_path()
		if not script_path then
			notify("error", script_error)
			return
		end

		local written, write_error = write_link_script(script_path, destination, source)
		if not written then
			notify("error", messages.temp_script_failed .. tostring(write_error))
			return
		end
	end

	-- Unix paths are passed as separate arguments. Windows folders use mklink
	-- /J directly; files run a generated temp script through the fixed Scoop
	-- sudo.cmd wrapper to elevate only the mklink operation.
	local ok, child, launch_error = pcall(launch_link, source, destination, is_dir, target_os, sudo_path, script_path)
	if not ok then
		notify("error", messages.launch_failed .. tostring(child))
		if script_path then
			os.remove(script_path)
		end
		return
	end

	if launch_error then
		notify("error", messages.launch_failed .. tostring(launch_error))
		if script_path then
			os.remove(script_path)
		end
		return
	end

	if not child then
		notify("error", messages.process_unavailable)
		if script_path then
			os.remove(script_path)
		end
		return
	end

	monitor_link(child, destination, script_path)
end

return {
	entry = entry,
}
