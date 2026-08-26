# Yazi Split Pane Link Plugin

pane-link.yazi is a Yazi plugin that creates a link to the active file or folder in the other pane displayed by terrakok/split-tabs.yazi. It does not copy data: both panes refer to the same underlying item, so edits made from either pane are visible from the other.

## Installation

~~~bash
ya pkg add terrakok/split-tabs
ya pkg add hironei/yazi_split_pane_link:pane-link
~~~

## Configuration

~~~toml
[[mgr.prepend_keymap]]
on = [ "g", "l" ]
run = "plugin pane-link"
desc = "Link selected item to the other pane"
~~~

Place the cursor on a file or folder in the active pane and press g then l to open the link-name prompt. Pressing Enter with an empty name keeps the original basename; entering a name creates the link with that name in the other pane. On Git Bash for Windows, files use mklink through %USERPROFILE%\scoop\shims\sudo.cmd, folders use mklink /J, and WSL/Linux/macOS use ln -s. See [pane-link.yazi/README.md](pane-link.yazi/README.md) for details.

## Tests

~~~bash
lua ./tests/test_main.lua
~~~

## License

MIT License. See [LICENSE](LICENSE) for details.
