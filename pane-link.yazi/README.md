# pane-link.yazi

`terrakok/split-tabs.yazi` の2ペイン間で、アクティブ側のファイルまたはフォルダを、反対側の現在ディレクトリへ同名のリンクとして作成するYaziプラグインです。コピーは作らないため、片方で編集した内容は同じ実体を参照するもう片方にも反映されます。

## 依存関係

| 依存関係 | 条件 |
| --- | --- |
| 対象環境 | Git Bash / WSL / Linux / macOS |
| Yazi / `ya` | 26.5.6 以上、同じバージョン |
| `terrakok/split-tabs.yazi` | 2ペイン表示に必須 |
| リンクコマンド | Git Bashでは `cmd.exe` の `mklink`、Unix系では `ln` |

Git Bash（Windows）ではファイルに `mklink`、フォルダに `mklink /J` を使います。`/J` はディレクトリジャンクションで、フォルダの実体を二重に持たないために使います。ファイルのシンボリックリンク作成にはDeveloper Modeまたは適切な権限が必要になる場合があります。WSL/Linux/macOSではファイル・フォルダとも `ln -s` を使います。

## インストール

まず `split-tabs.yazi` を導入します。

```bash
ya pkg add terrakok/split-tabs
```

次にこのプラグインを導入します。

```bash
ya pkg add hironei/yazi_split_pane_link:pane-link
```

更新・削除は次のコマンドです。

```bash
ya pkg upgrade
ya pkg delete hironei/yazi_split_pane_link:pane-link
```

`ya pkg` はYaziのパッケージ管理情報を更新します。monorepoのサブディレクトリ指定は `owner/repository:subdirectory` 形式です。

## キーマップ

Yaziを実行する環境の `keymap.toml` に追加します。

```toml
[[mgr.prepend_keymap]]
on = [ "g", "l" ]
run = "plugin pane-link"
desc = "Link selected item to the other pane"
```

設定例は [`examples/keymap.toml`](../examples/keymap.toml) にあります。

## 使い方

1. `split-tabs.yazi` で2ペインを表示します。
2. リンク元にしたいペインをアクティブにします。
3. ファイルまたはフォルダへカーソルを置きます。明示選択が1件ある場合は、その選択が使われます。
4. `g` → `l` を押します。

リンクは反対側ペインの現在ディレクトリに、元の basename と同じ名前で作られます。アクティブペインを切り替えると、sourceとdestinationも反転します。物理的な画面左・右の順序は保証しません。

## 対象の決定と失敗時の動作

- 明示選択1件を優先し、選択がなければカーソル位置を使います。
- 明示選択が2件以上、対象がない、2タブでない場合は作成しません。
- ファイルとフォルダは対象にできます。
- 壊れたシンボリックリンク、特殊ファイル、アーカイブ内・リモートURLは対象外です。
- destinationに同名の項目がある場合は上書きせず、リンクコマンドの失敗を通知します。自動改名や既存項目の削除はしません。
- ハードリンク（`mklink /H`）やファイルコピーへのフォールバックは行いません。
- パスは個別のコマンド引数として渡すため、空白・日本語・括弧を含むパスもシェルのクォートに依存しません。

作成成功後はYaziにrefreshを通知します。作成したリンクはsourceのパスを指すため、sourceを移動・削除するとリンク先も利用できなくなります。

## 制約と確認

このプラグインはYaziの公開Lua APIと `split-tabs.yazi` の2タブモデルを使用します。YaziのAPIは変更される可能性があるため、更新後は動作確認してください。

次の確認はモックテストで行えます。

```bash
lua ./tests/test_main.lua
```

モックテストは実Yazi UI、Windowsのリンク作成権限、実ファイルシステム、Git Bash/WSLの環境差を保証しません。
