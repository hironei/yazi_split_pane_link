# pane-link.yazi

pane-link.yazi is a Yazi plugin that creates a link from a file or folder in the active pane to the other pane's current directory. It does not copy data, so edits made from either pane are visible through the link.

## Dependencies

| Dependency | Requirement |
| --- | --- |
| Target environment | Git Bash / WSL / Linux / macOS |
| Yazi / ya | 26.5.6 or later, using the same version; Yazi 26.8.15+ selected `File` entries are resolved through `.url` |
| terrakok/split-tabs.yazi | Required for the two-pane view |
| Link command | cmd.exe mklink on Git Bash; ln on Unix-like systems |
| Windows file links | %USERPROFILE%\scoop\shims\sudo.cmd is required |

On Git Bash for Windows, folders use mklink /J directly. Files use %USERPROFILE%\scoop\shims\sudo.cmd cmd.exe /d /c mklink so that only the link-creation operation is elevated through UAC. Developer Mode is not used. If sudo.cmd is unavailable, file links fail before execution. On WSL/Linux/macOS, both files and folders use ln -s.

## Installation

Install split-tabs.yazi first:

~~~bash
ya pkg add terrakok/split-tabs
~~~

Then install this plugin:

~~~bash
ya pkg add hironei/yazi_split_pane_link:pane-link
~~~

Use the following commands to update or remove packages:

~~~bash
ya pkg upgrade
ya pkg delete hironei/yazi_split_pane_link:pane-link
~~~

ya pkg updates Yazi's package metadata. Monorepo subdirectory syntax is owner/repository:subdirectory.

## Keymap

Add the following to the keymap.toml used by Yazi:

~~~toml
[[mgr.prepend_keymap]]
on = [ "g", "l" ]
run = "plugin pane-link"
desc = "Link selected item to the other pane"
~~~

A complete example is available in [examples/keymap.toml](../examples/keymap.toml).

## Usage

1. Display two panes with split-tabs.yazi.
2. Activate the pane containing the link source.
3. Place the cursor on a file or folder. If exactly one item is explicitly selected, that item is used.
4. Press g then l.
5. Enter a link name and press Enter. Leave it empty to use the original basename. Press Esc or otherwise cancel to skip link creation.

The link is created in the other pane's current directory using the entered name. An empty name uses the original basename. Switching the active pane reverses the source and destination. The physical left/right order of panes is not guaranteed.

## Target selection and failure behavior

- One explicitly selected item takes priority; its `File.url` is resolved to a URL before validation. Older direct `Url` entries remain compatible; otherwise the hovered item is used.
- Link creation is skipped when more than one item is explicitly selected, no target exists, or the view does not have exactly two tabs.
- Both files and folders can be linked.
- Broken symbolic links, special files, archive contents, and remote URLs are rejected.
- An existing destination item is never overwritten. The link command fails and the user is notified. The plugin does not rename or delete existing items automatically.
- The link name must be a single basename. An empty name uses the original basename. Path separators and characters that are invalid on Windows are rejected.
- Hard links (mklink /H) and file-copy fallbacks are not used.
- Paths are passed as individual command arguments. Windows file links pass through Scoop sudo.cmd argument handling, so paths containing spaces, Japanese characters, or parentheses must be verified on a real machine.

After a successful link operation, the plugin emits a refresh event to Yazi. The created link points to the source path, so moving or deleting the source makes the link unusable.

## Limitations and validation

This plugin uses Yazi's public Lua API and the two-tab model provided by split-tabs.yazi. Yazi's API may change; verify behavior after upgrades.

The following checks are covered by the mock test:

~~~bash
lua ./tests/test_main.lua
~~~

The mock test does not guarantee behavior in the real Yazi UI, UAC prompts, Windows link-creation permissions, the real filesystem, or Git Bash/WSL environment differences.
