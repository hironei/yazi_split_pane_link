local source = arg[1] or "pane-link.yazi/main.lua"

local notifications = {}
local emitted = {}
local launched = {}
local spawn_result = {}
local inspect_result = { cha = {}, err = nil }
local target_os = "linux"

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
	})
end

function Url(path)
	return url(path)
end

local function cwd(path)
	return {
		join = function(_, name)
			return url(path .. "/" .. name)
		end,
	}
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
	target_os = function()
		return target_os
	end,
	emit = function(action, args)
		emitted[#emitted + 1] = { action = action, args = args }
	end,
}

fs = {
	cha = function()
		return inspect_result.cha, inspect_result.err
	end,
}

local command = {}
function command:arg(args)
	self.args = args
	return self
end

function command:spawn()
	launched[#launched + 1] = {
		program = self.program,
		args = self.args,
	}
	return spawn_result.child, spawn_result.err
end

function Command(program)
	return setmetatable({ program = program }, { __index = command })
end

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
assert_equal(emitted[1].action, "refresh", "refresh action")
assert_equal(notifications[1].level, "info", "success notification")

-- macOS follows the same Unix symlink path as Linux/WSL.
reset()
target_os = "macos"
run({
	tab({}, file([[/source/編集対象.txt]]), "/source"),
	tab({}, file([[/other/other.txt]]), "/other"),
})
assert_equal(launched[1].program, "ln", "macOS program")
assert_equal(launched[1].args[1], "-s", "macOS symlink option")

-- Windows uses cmd.exe for the mklink builtin; files use symbolic links.
reset()
target_os = "windows"
run({
	tab({}, file([[C:/work/left pane/file.txt]]), "/source"),
	tab({}, file([[C:/work/right.txt]]), [[C:/dest pane]]),
})
assert_equal(launched[1].program, "cmd.exe", "Windows program")
assert_equal(launched[1].args[1], "/d", "cmd echo mode")
assert_equal(launched[1].args[2], "/c", "cmd command mode")
assert_equal(launched[1].args[3], "mklink", "mklink command")
assert_equal(launched[1].args[4], [[C:/dest pane/file.txt]], "Windows file link path")
assert_equal(launched[1].args[5], [[C:/work/left pane/file.txt]], "Windows file target path")

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
