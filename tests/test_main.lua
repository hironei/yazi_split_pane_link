local source = arg[1] or "pane-link.yazi/main.lua"

local notifications = {}
local emitted = {}
local launched = {}
local spawn_result = {}
local inspect_result = { cha = {}, err = nil }
local target_os = "linux"
local sudo_exists = true
local input_value = ""
local input_event = 1
local input_requests = {}
local temp_dir_value = "C:\\Users\\test\\AppData\\Local\\Temp"
local native_getenv = os.getenv
os.getenv = function(name)
	if name == "USERPROFILE" then
		return "C:/Users/test"
	end
	if name == "TEMP" or name == "TMP" then
		return temp_dir_value
	end
	return native_getenv(name)
end

local io_open_calls = {}
local written_files = {}
local io_open_result = { ok = true, err = nil }
io.open = function(path, mode)
	io_open_calls[#io_open_calls + 1] = { path = path, mode = mode }
	if not io_open_result.ok then
		return nil, io_open_result.err
	end

	local chunks = {}
	local handle = {}
	function handle:write(s)
		chunks[#chunks + 1] = s
		return true
	end
	function handle:close()
		written_files[path] = table.concat(chunks)
		return true
	end
	return handle
end

local removed_files = {}
os.remove = function(path)
	removed_files[#removed_files + 1] = path
	return true
end

local function basename(path)
	return path:match("[^/\\]+$")
end

local function url(path, opts)
	opts = opts or {}
	return setmetatable({
		path = path,
		name = opts.name or basename(path),
		domain = opts.domain,
		is_archive = opts.is_archive or false,
	}, {
		__tostring = function(value)
			return value.path
		end,
		__index = {
			join = function(value, name)
				return url(value.path .. "/" .. name)
			end,
		},
	})
end

function Url(path)
	return url(path)
end

local function cwd(path)
	local value = url(path)
	function value:join(name)
		return url(self.path .. "/" .. name)
	end
	return value
end

local successful_child = {}
function successful_child:wait()
	return { success = true, code = 0 }, nil
end

ya = {
	sync = function(fn)
		return fn
	end,
	notify = function(notification)
		notifications[#notifications + 1] = notification
	end,
	input = function(options)
		input_requests[#input_requests + 1] = options
		return input_value, input_event
	end,
	target_os = function()
		return target_os
	end,
	emit = function(action, args)
		emitted[#emitted + 1] = { action = action, args = args }
	end,
}

fs = {
	cha = function(path)
		if tostring(path):lower():match("[/\\\\]scoop[/\\\\]shims[/\\\\]sudo%.cmd$") then
			if not sudo_exists then
				return nil, "not found"
			end

			return { is_dir = false }, nil
		end

		return inspect_result.cha, inspect_result.err
	end,
}

local command = {}
function command:arg(args)
	self.args = args
	return self
end

function command:stdout(mode)
	self.stdout_mode = mode
	return self
end

function command:stderr(mode)
	self.stderr_mode = mode
	return self
end

function command:spawn()
	launched[#launched + 1] = {
		program = self.program,
		args = self.args,
		stdout = self.stdout_mode,
		stderr = self.stderr_mode,
	}
	return spawn_result.child, spawn_result.err
end

Command = setmetatable({ NULL = "null", PIPED = "piped", INHERIT = "inherit" }, {
	__call = function(_, program)
		return setmetatable({ program = program }, { __index = command })
	end,
})

local plugin = assert(loadfile(source))()

local function file(path, opts)
	opts = opts or {}
	return {
		url = url(path, opts),
		cha = {
			is_orphan = opts.is_orphan or false,
			is_block = opts.is_block or false,
			is_char = opts.is_char or false,
			is_fifo = opts.is_fifo or false,
			is_sock = opts.is_sock or false,
		},
	}
end

local function tab(selected, hovered, path)
	return {
		selected = selected or {},
		current = {
			hovered = hovered,
			cwd = path and cwd(path) or nil,
		},
	}
end

local function reset()
	notifications = {}
	emitted = {}
	launched = {}
	spawn_result = { child = successful_child, err = nil }
	inspect_result = { cha = {}, err = nil }
	target_os = "linux"
	sudo_exists = true
	input_value = ""
	input_event = 1
	input_requests = {}
	temp_dir_value = "C:\\Users\\test\\AppData\\Local\\Temp"
	io_open_calls = {}
	written_files = {}
	io_open_result = { ok = true, err = nil }
	removed_files = {}
end

local function run(tabs, active_index)
	tabs.idx = active_index or 1
	cx = { tabs = tabs }
	plugin.entry()
end

local function assert_equal(actual, expected, message)
	assert(actual == expected, (message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function assert_notification(level, fragment)
	assert_equal(#notifications, 1, "notification count")
	assert_equal(notifications[1].level, level, "notification level")
	assert(notifications[1].content:find(fragment, 1, true), "notification did not contain: " .. fragment)
end

local function assert_no_link(fragment)
	assert_equal(#launched, 0, fragment .. " launch count")
	assert_notification("warn", fragment)
end

-- A hovered file is linked to the other pane, preserving special characters.
reset()
run({
	tab({}, file([[C:/work/left pane/左 (1).txt]]), "/unused"),
	tab({}, file([[C:/work/right.txt]]), "/dest pane/反対"),
})
assert_equal(launched[1].program, "ln", "program")
assert_equal(launched[1].args[1], "-s", "symlink option")
assert_equal(launched[1].args[2], [[C:/work/left pane/左 (1).txt]], "source path")
assert_equal(launched[1].args[3], [[/dest pane/反対/左 (1).txt]], "destination path")
assert_equal(launched[1].stdout, "null", "ln stdout suppressed")
assert_equal(launched[1].stderr, "null", "ln stderr suppressed")
assert_equal(emitted[1].action, "refresh", "refresh action")
assert_equal(emitted[2].action, "tab_switch", "switch to other pane to refresh it")
assert_equal(emitted[2].args[1], 1, "other pane tab_switch index")
assert_equal(emitted[3].action, "tab_switch", "switch back to the original active pane")
assert_equal(emitted[3].args[1], 0, "original pane tab_switch index")
assert_equal(notifications[1].level, "info", "success notification")
assert_equal(input_requests[1].value, "", "empty link name input")

-- A custom link name is used for the destination only.
reset()
input_value = "renamed.txt"
run({
	tab({}, file([[C:/work/source.txt]]), "/source"),
	tab({}, file([[C:/work/other.txt]]), "/dest"),
})
assert_equal(launched[1].args[3], [[/dest/renamed.txt]], "custom destination name")

-- Canceling the name prompt does not launch a link command.
reset()
input_event = 2
run({
	tab({}, file([[C:/work/source.txt]]), "/source"),
	tab({}, file([[C:/work/other.txt]]), "/dest"),
})
assert_equal(#launched, 0, "cancel launch count")
assert_equal(#notifications, 0, "cancel notification count")

-- A name must remain a single safe basename.
reset()
input_value = "nested/renamed.txt"
run({
	tab({}, file([[C:/work/source.txt]]), "/source"),
	tab({}, file([[C:/work/other.txt]]), "/dest"),
})
assert_equal(#launched, 0, "invalid name launch count")
assert_notification("warn", "リンク名")

-- macOS follows the same Unix symlink path as Linux/WSL.
reset()
target_os = "macos"
run({
	tab({}, file([[/source/編集対象.txt]]), "/source"),
	tab({}, file([[/other/other.txt]]), "/other"),
})
assert_equal(launched[1].program, "ln", "macOS program")
assert_equal(launched[1].args[1], "-s", "macOS symlink option")

-- Windows file links use Scoop sudo.cmd to elevate only the mklink operation.
reset()
target_os = "windows"
run({
	tab({}, file([[C:/work/left pane/file.txt]]), "/source"),
	tab({}, file([[C:/work/right.txt]]), [[C:/dest pane]]),
})
assert_equal(launched[1].program, "cmd.exe", "Windows program")
assert_equal(launched[1].args[1], "/d", "cmd echo mode")
assert_equal(launched[1].args[2], "/c", "cmd command mode")
local expected_sudo = "C:/Users/test/scoop/shims/sudo.cmd"
assert_equal(launched[1].args[3], expected_sudo, "sudo.cmd path")
assert_equal(launched[1].args[4], "cmd.exe", "elevated command")
assert_equal(launched[1].args[5], "/d", "elevated cmd echo mode")
assert_equal(launched[1].args[6], "/c", "elevated cmd command mode")
local script_path = launched[1].args[7]
assert(script_path:match("^C:/Users/test/AppData/Local/Temp/pane%-link%-%x+%.cmd$"), "temp script path shape: " .. tostring(script_path))
assert_equal(launched[1].stdout, "null", "mklink stdout suppressed")
assert_equal(launched[1].stderr, "null", "mklink stderr suppressed")

-- The temp script contains the actual mklink call, with its own output
-- suppressed so sudo.cmd's AttachConsole can't leak it into Yazi's console,
-- and it is only a single argument, so sudo.cmd's own re-parsing of its
-- arguments as one string can no longer split a path apart.
local script_content = written_files[script_path]
assert(script_content, "temp script was written")
assert(script_content:find('mklink "C:/dest pane/file.txt" "C:/work/left pane/file.txt" >nul 2>&1', 1, true), "script runs mklink with quoted dest/source and suppressed output: " .. tostring(script_content))
assert(script_content:find("@echo off", 1, true), "script disables command echo")
assert(script_content:find("exit /b %errorlevel%", 1, true), "script propagates mklink's exit code")
assert_equal(removed_files[1], script_path, "temp script cleaned up after the link command finishes")

-- Windows file links fail before launch when Scoop sudo.cmd is unavailable.
reset()
target_os = "windows"
sudo_exists = false
run({
	tab({}, file([[C:/work/left pane/file.txt]]), "/source"),
	tab({}, file([[C:/work/right.txt]]), [[C:/dest pane]]),
})
assert_equal(#launched, 0, "missing sudo launch count")
assert_notification("error", "sudo.cmd")
assert_equal(#io_open_calls, 0, "no temp script is written when sudo.cmd is unavailable")

-- Windows file links fail before launch when %TEMP%/%TMP% are unavailable.
reset()
target_os = "windows"
temp_dir_value = nil
run({
	tab({}, file([[C:/work/left pane/file.txt]]), "/source"),
	tab({}, file([[C:/work/right.txt]]), [[C:/dest pane]]),
})
assert_equal(#launched, 0, "missing temp dir launch count")
assert_notification("error", "一時ディレクトリ")

-- Windows file links fail before launch when the temp script can't be written.
reset()
target_os = "windows"
io_open_result = { ok = false, err = "disk full" }
run({
	tab({}, file([[C:/work/left pane/file.txt]]), "/source"),
	tab({}, file([[C:/work/right.txt]]), [[C:/dest pane]]),
})
assert_equal(#launched, 0, "temp script write failure launch count")
assert_notification("error", "disk full")

-- Windows folders use /J as requested; /H is never used.
reset()
target_os = "windows"
inspect_result.cha = { is_dir = true }
run({
	tab({}, file([[C:/work/source folder]]), "/source"),
	tab({}, file([[C:/work/right.txt]]), [[C:/dest pane]]),
})
assert_equal(launched[1].program, "cmd.exe", "Windows directory program")
assert_equal(launched[1].args[4], "/J", "junction option")
assert_equal(launched[1].args[5], [[C:/dest pane/source folder]], "Windows directory link path")
assert_equal(launched[1].args[6], [[C:/work/source folder]], "Windows directory target path")

-- A selected folder takes precedence over the hovered item.
reset()
inspect_result.cha = { is_dir = true }
run({
	tab({ url([[C:/selected/フォルダ]], { name = "フォルダ" }) }, file([[C:/hovered.txt]]), "/source"),
	tab({}, file([[C:/other.txt]]), "/target"),
})
assert_equal(launched[1].args[2], [[C:/selected/フォルダ]], "selected source path")
assert_equal(launched[1].args[3], [[/target/フォルダ]], "selected destination path")

-- The active tab is always the source and the other tab supplies the destination.
reset()
run({
	tab({}, file([[C:/first.txt]]), "/first"),
	tab({}, file([[C:/second.txt]]), "/second"),
}, 2)
assert_equal(launched[1].args[2], [[C:/second.txt]], "reversed source path")
assert_equal(launched[1].args[3], [[/first/second.txt]], "reversed destination path")
assert_equal(emitted[2].action, "tab_switch", "reversed switch to other pane to refresh it")
assert_equal(emitted[2].args[1], 0, "reversed other pane tab_switch index")
assert_equal(emitted[3].action, "tab_switch", "reversed switch back to the original active pane")
assert_equal(emitted[3].args[1], 1, "reversed original pane tab_switch index")

-- Invalid target states do not launch a process.
reset()
run({ tab({ url([[C:/one.txt]]), url([[C:/two.txt]]) }, file([[C:/left.txt]]), "/target"), tab({}, file([[C:/right.txt]]), "/other") })
assert_no_link("アクティブペインの選択ファイルは1つ")

reset()
run({ tab({}, nil, "/target"), tab({}, file([[C:/right.txt]]), "/other") })
assert_no_link("アクティブペインにリンク対象がありません")

reset()
run({ tab({}, file([[C:/left.txt]]), "/target") })
assert_no_link("リンク作成には2つのタブが必要です")

reset()
run({ tab({}, file([[C:/device]] , { is_block = true }), "/target"), tab({}, file([[C:/right.txt]]), "/other") })
assert_no_link("通常ファイルまたはフォルダだけ")

reset()
run({ tab({}, file([[C:/broken.link]], { is_orphan = true }), "/target"), tab({}, file([[C:/right.txt]]), "/other") })
assert_no_link("壊れたシンボリックリンク")

reset()
run({ tab({}, file([[sftp://server/file]], { domain = "server" }), "/target"), tab({}, file([[C:/right.txt]]), "/other") })
assert_no_link("ローカルファイルシステム")

reset()
run({ tab({}, file([[C:/archive.zip/file]], { is_archive = true }), "/target"), tab({}, file([[C:/right.txt]]), "/other") })
assert_no_link("アーカイブ内")

-- File inspection errors and broken/special filesystem entries are rejected.
reset()
inspect_result = { cha = nil, err = "not found" }
run({ tab({}, file([[C:/missing.txt]]), "/target"), tab({}, file([[C:/right.txt]]), "/other") })
assert_no_link("リンク対象を確認できませんでした: not found")

reset()
inspect_result.cha = { is_orphan = true }
run({ tab({}, file([[C:/broken.link]]), "/target"), tab({}, file([[C:/right.txt]]), "/other") })
assert_no_link("壊れたシンボリックリンク")

reset()
inspect_result.cha = { is_sock = true }
run({ tab({}, file([[C:/socket]]), "/target"), tab({}, file([[C:/right.txt]]), "/other") })
assert_no_link("通常ファイルまたはフォルダだけ")

-- Process-start errors, wait errors, and non-zero exit statuses are notified.
reset()
spawn_result = { child = nil, err = "ln not found" }
run({ tab({}, file([[C:/left.txt]]), "/target"), tab({}, file([[C:/right.txt]]), "/other") })
assert_notification("error", "ln not found")

reset()
local wait_error_child = {}
function wait_error_child:wait()
	error("wait failed")
end
spawn_result = { child = wait_error_child, err = nil }
run({ tab({}, file([[C:/left.txt]]), "/target"), tab({}, file([[C:/right.txt]]), "/other") })
assert_notification("error", "wait failed")

reset()
local failed_child = {}
function failed_child:wait()
	return { success = false, code = 17 }, nil
end
spawn_result = { child = failed_child, err = nil }
run({ tab({}, file([[C:/left.txt]]), "/target"), tab({}, file([[C:/right.txt]]), "/other") })
assert_notification("error", "終了コード 17")

print("pane-link.yazi tests passed")
