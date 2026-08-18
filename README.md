# Yazi Split Pane Link Plugin

Yaziの `terrakok/split-tabs.yazi` で表示した2ペイン間に、アクティブ側のファイルまたはフォルダのリンクを作成する `pane-link.yazi` プラグインです。コピーを作らず同じ実体を参照するため、片方の編集結果はもう片方にも反映されます。

## インストール

```bash
ya pkg add terrakok/split-tabs
ya pkg add hironei/yazi_split_pane_link:pane-link
```

## 設定

```toml
[[mgr.prepend_keymap]]
on = [ "g", "l" ]
run = "plugin pane-link"
desc = "Link selected item to the other pane"
```

アクティブ側のファイルまたはフォルダにカーソルを置き、`g` → `l` を押すとリンク名の入力欄が表示されます。空欄のままEnterすると元のbasenameを維持し、名前を入力すると反対側ペインにその名前でリンクを作成します。Git BashのWindowsではファイルに `%USERPROFILE%\scoop\shims\sudo.cmd` 経由の `mklink`、フォルダに `mklink /J`、WSL/Linux/macOSでは `ln -s` を使います。詳細は [`pane-link.yazi/README.md`](pane-link.yazi/README.md) を参照してください。

## テスト

```bash
lua ./tests/test_main.lua
```

## ライセンス

MIT License。詳細は [`LICENSE`](LICENSE) を参照してください。
