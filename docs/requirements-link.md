# split-pane-link Requirements

## Purpose

Create a symbolic link for the active file or folder in the other pane displayed by terrakok/split-tabs.yazi. The link is created in the other pane's current directory and refers to the same underlying item rather than copying it.

## Scope

- The plugin name is pane-link.yazi.
- Use the two tabs provided by split-tabs.yazi as the active and other panes.
- If exactly one item is explicitly selected in the active pane, use that URL; otherwise use the item under the cursor.
- Accept a link name before execution. An empty input uses the basename of the target URL; a non-empty input uses the entered basename.
- Support regular files and folders. Create links that refer to the same underlying item; never copy the item.
- On Linux/WSL/macOS, use ln -s for both files and folders. On Windows, use mklink through %USERPROFILE%\scoop\shims\sudo.cmd for files and mklink /J for folders. Use /J for folders to avoid maintaining a second copy.
- Use the entered link name, or the target URL basename when the input is empty. Create the destination under the other tab's current.cwd.
- Invoke OS-specific external commands with individual arguments. Never build a command string from user input.

## Non-functional requirements

- Target Yazi 26.5.6 or later.
- On Git Bash, use Windows mklink and Scoop sudo.cmd only for file links. On WSL/Linux/macOS, use ln -s.
- Preserve argument boundaries for paths containing spaces, Japanese characters, parentheses, or other special characters.
- Do not overwrite an existing destination item.
- Refresh Yazi after execution so the result can be confirmed in both panes.
- Do not change selection state, cursor position, or either tab's current directory.
- Do not leak link-command stdout or stderr into Yazi's terminal screen.

## Errors and boundary conditions

- Do not execute when the tab count is not two.
- Do not execute when more than one item is explicitly selected.
- Do not execute when there is no target, the basename cannot be obtained, or the other pane's current directory cannot be obtained.
- Reject archive URLs, remote URLs, and other URLs that the link command cannot handle before execution.
- Reject broken symbolic links, special files, and targets whose filesystem metadata cannot be obtained.
- If an item with the same name exists at the destination, notify the ln/mklink failure without deleting, overwriting, or automatically renaming anything.
- Do not create a link when the name prompt is canceled, the name contains path separators, or the name is invalid on Windows. Notify invalid names.
- Notify command-start failures, failures to obtain the exit status, and non-zero exit codes.
- For Windows file links, do not execute when %TEMP%/%TMP% cannot be obtained or when the temporary script cannot be written.

## Security and compatibility

- On Unix-like systems, pass arguments as Command("ln"):arg { "-s", source, destination }. On Windows, call only the fixed mklink command from Command("cmd.exe"), because mklink is a cmd built-in. Use regular mklink /J for folders. For files, write the mklink call to a temporary .cmd script and run it elevated through %USERPROFILE%\scoop\shims\sudo.cmd cmd.exe /d /c. Do not use hard links (/H) or copy operations. Scoop sudo.cmd rejoins and reparses its arguments as one string, so do not pass destination/source directly; pass one temporary script path to avoid path corruption during multi-stage parsing.
- The plugin never deletes or overwrites existing files. Source and destination refer to the same underlying item, so edits made through either path are visible through the other.
- Limit the source to the URL selected in Yazi. Do not accept paths from arbitrary plugin arguments.
- Windows file links require %USERPROFILE%\scoop\shims\sudo.cmd and may display a UAC prompt. Developer Mode is not a prerequisite.

## Acceptance criteria

1. With two tabs and a file under the cursor, execution opens the link-name prompt and creates a link in the other pane's current directory. Empty input creates a link with the original basename. Both panes show the result after creation, and command output does not remain on the Yazi screen.
2. Folders behave the same way.
3. One explicit selection takes priority over the cursor, the link name can be changed, and switching the active tab reverses source and destination.
4. Paths containing spaces, Japanese characters, and parentheses remain intact as command arguments.
5. More than one selected item, no target, a tab count other than two, special files, broken links, and an existing destination do not create a link and produce a notification.
6. Linux/WSL/macOS select ln -s. Windows selects a temporary-script and sudo.cmd based mklink path for files and mklink /J for folders. Missing sudo.cmd, temporary-script write failures, command-start failures, UAC cancellation, and non-zero exits produce notifications.
7. The Lua mock test reproduces the normal, boundary, and error cases above.
