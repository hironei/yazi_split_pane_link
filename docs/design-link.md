# split-pane-link Design

## Structure

~~~
pane-link.yazi/main.lua  -- Yazi plugin entry point
tests/test_main.lua      -- Lua mock tests
examples/keymap.toml     -- keymap example
pane-link.yazi/README.md -- user-facing setup and behavior
~~~

entry runs in an asynchronous context. It uses ya.sync to obtain only the required strings from cx.tabs, then performs filesystem metadata access and Command:spawn / Child:wait on the asynchronous side.

## Target selection

1. Confirm that #cx.tabs == 2.
2. Treat cx.tabs.idx as the active tab and the other tab as the destination tab.
3. If the active tab has one selected item, use that URL.
4. If it has no selected items, use current.hovered.url. More than one selected item is an error.
5. Obtain the source URL name and the destination tab's current.cwd.
6. Use ya.input to obtain a link name. Use the source URL name for empty input; otherwise validate the input as a basename and build the destination URL with current.cwd:join(name). Do not create a link after cancellation or invalid input.

Do not infer physical left/right ordering. As with split-tabs.yazi, the public contract is the active-tab/other-tab order.

## File-type validation

Use fs.cha(Url(source), true) to obtain metadata after following the link target. Allow is_dir; reject is_orphan, block, char, fifo, and socket entries. Reject metadata errors. Use is_dir to select /J on Windows.

Restrict source and destination to local URLs. Do not pass URLs with a domain, or URLs without a basename or parent, to ln.

## Link creation and notifications

On Unix-like systems, run:

~~~
Command("ln")
  :arg { "-s", source, destination }
  :spawn()
~~~

On Windows, mklink is a cmd built-in, so run the fixed command from cmd.exe. Use a normal symbolic link for files, /J for directory junctions, and no /H hard link or copy fallback.

For folders:

~~~
Command("cmd.exe")
  :arg { "/d", "/c", "mklink", "/J", destination, source }
  :spawn()
~~~

For files, elevate through %USERPROFILE%\scoop\shims\sudo.cmd. Do not pass destination and source directly. Instead, create a temporary .cmd script in %TEMP%/%TMP% and pass only its path:

~~~
Command("cmd.exe")
  :arg {
    "/d", "/c", sudo_path,
    "cmd.exe", "/d", "/c", script_path,
  }
~~~

The temporary script has this shape, with destination and source always double-quoted:

~~~
@echo off
mklink "destination" "source" >nul 2>&1
exit /b %errorlevel%
~~~

The temporary script avoids a known Scoop sudo.cmd argument-reparsing problem. The wrapper rejoins arguments into one string and reparses them across the elevated process and PowerShell. Passing a raw mklink destination/source argument list can cause part of a Windows path such as C:\Users\... to be interpreted as an invalid mklink switch such as /Users. Passing one script path removes the multi-stage parsing of the actual paths. The script also suppresses mklink output explicitly with >nul 2>&1.

If sudo.cmd is missing, %TEMP%/%TMP% cannot be obtained, or the temporary script cannot be written, do not start mklink; notify the user. Remove the temporary script with os.remove after child:wait() completes, whether the command succeeds or fails. Folders do not use UAC elevation or a temporary script.

The implementation does not leave nil elements in argument arrays and adds /J only for folders. mklink receives the link path before the target path, so pass destination first. Do not pre-check destination existence; treating the command's failure as authoritative avoids increasing the race window. Notify cancellation, invalid names, missing sudo.cmd, temporary-script failures, command-start failures, UAC cancellation, wait failures, and non-zero exits.

Set stdout and stderr to Command.NULL for ln and mklink /J. Without this, Windows child-process output such as mklink completion text can be written directly into Yazi's terminal buffer and leave artifacts over the TUI. File links additionally require output suppression inside the temporary script because sudo.cmd reattaches the elevated process to the original console.

After success, emit ya.emit("refresh", {}) and then emit ya.emit("tab_switch", { other_index }) followed by ya.emit("tab_switch", { active_index }), then show the completion notification. Yazi's Mgr refresh/watch commands target only the active tab, and filesystem-watch update_files events are not delivered to the inactive tab. The tab_switch round trip uses its internal refresh for the other tab and then returns to the original active tab. If the tab count is no longer two when the command completes, skip the round trip and refresh only the active tab. tab_switch does not change selection, cursor, or either tab's current.cwd.

## Test seam

tests/test_main.lua mocks ya.sync, ya.notify, ya.emit, fs.cha, Command, Child, and Url. It verifies:

- Files and folders; empty input and renamed links; input cancellation; invalid names; path arguments; selection priority; active-tab reversal; refresh; the tab_switch round trip that refreshes the other pane; and stdout/stderr suppression.
- Temporary-script contents for file links, including the mklink call, output suppression, exit-code propagation, and cleanup after execution; notifications when %TEMP%/%TMP% is unavailable or the script cannot be written.
- Two-tab validation, multiple selections, missing targets, special files, broken links, and metadata failures.
- Command-start errors, wait errors, and non-zero exits, including existing destinations that cause the link command to fail.

## Compatibility and operations

The plugin uses Yazi's public Lua API and the two-tab model from split-tabs.yazi. Windows file links additionally require Scoop sudo.cmd. Git Bash uses cmd.exe/mklink; WSL/Linux/macOS use ln. The mock test does not guarantee behavior in the real Yazi UI, UAC prompts, permissions, or real-filesystem link creation.
