# split-pane-link 設計

## 構成

```
pane-link.yazi/main.lua  -- Yazi plugin entry point
tests/test_main.lua      -- Lua mock tests
examples/keymap.toml     -- keymap example
pane-link.yazi/README.md -- user-facing setup and behavior
```

`entry` は非同期コンテキストで実行する。`ya.sync` で `cx.tabs` から必要な文字列だけを取得し、ファイルシステム情報取得と `Command:spawn` / `Child:wait` は非同期側で行う。

## 対象の選択

1. `#cx.tabs == 2` を確認する。
2. `cx.tabs.idx` をアクティブタブとして、もう一方を destination タブとする。
3. アクティブタブの `selected` が1件ならそのURLを使う。
4. 選択が0件なら `current.hovered.url` を使う。2件以上はエラーにする。
5. source URLの `name` と destination タブの `current.cwd` を取得する。
6. `ya.input` でリンク名を受け取り、空入力ならsource URLの `name` を使い、入力値なら検証済みのbasenameとして `current.cwd:join(name)` でdestination URLを構成する。キャンセルや不正な名前では作成しない。

物理的な画面の左右は推測しない。`split-tabs.yazi` と同じく、active tab / other tab の順だけを公開契約として扱う。

## ファイル種別確認

`fs.cha(Url(source), true)` でリンク先を追跡した属性を取得する。`is_dir` は許可し、`is_orphan`、block/char/fifo/socket は拒否する。属性取得エラーも拒否する。`is_dir` はWindowsで `/J` を選ぶために使う。

source と destination はローカルURLに限定する。`domain` があるURL、または basename / parent を持たないURLは `ln` に渡さない。

## リンク作成と通知

Unix系では次を実行する。

```
Command("ln")
  :arg { "-s", source, destination }
  :spawn()
```

Windowsでは `mklink` がcmdの組み込みコマンドなので、次の固定コマンドを `cmd.exe` から実行する。ファイルは既定のシンボリックリンク、フォルダは `/J` のディレクトリジャンクションとする。`/H` のハードリンクやコピーは使わない。

フォルダの場合:

```
Command("cmd.exe")
  :arg { "/d", "/c", "mklink", "/J", destination, source }
  :spawn()
```

ファイルの場合は `%USERPROFILE%\scoop\shims\sudo.cmd` を経由して、次のようにUAC昇格する。

```
Command("cmd.exe")
  :arg {
    "/d", "/c", sudo_path,
    "cmd.exe", "/d", "/c", "mklink", destination, source,
  }
```

`sudo.cmd` が存在しない場合は `mklink` を起動せず通知する。フォルダではUAC昇格を行わない。

実装では `nil` を配列要素に残さず、フォルダの場合だけ `/J` を追加する。`mklink` の引数順は `link target` なので、destinationを先に渡す。destinationの存在確認を先に行うと競合窓が増えるため、上書きしない各コマンドの失敗を正とする。入力キャンセルは作成せず終了し、不正なリンク名、`sudo.cmd` の欠落、起動失敗、UACキャンセル、wait失敗、非0終了は通知する。

`ln`/`mklink` の `Command` にはそれぞれ `:stdout(Command.NULL):stderr(Command.NULL)` を指定する。指定しないとWindowsでは子プロセスの標準出力（`mklink` の完了メッセージ等）がYaziの端末画面バッファへ直接書き込まれ、TUIの描画と重なって残像として残る。

終了成功時は `ya.emit("refresh", {})` を発行したうえで、`ya.emit("tab_switch", { other_index })` → `ya.emit("tab_switch", { active_index })` の順で発行し、完了通知を表示する。YaziのMgrコマンド（`refresh`/`watch`）は常にアクティブタブだけを対象にし、ファイルシステム監視によるリアクティブな `update_files` も非アクティブタブへは配信されない。そのため、反対側ペイン（非アクティブタブ）が作成直後のリンクを表示するには、`tab_switch` がその内部で対象タブに対して `refresh` を実行する仕組みを利用し、反対側タブへ一旦切り替えてから元のアクティブタブへ戻す。タブ数が2以外（作成待機中にタブが増減した場合）はこの往復をスキップし、アクティブタブの `refresh` のみ行う。選択状態・カーソル・各タブの `current.cwd` は `tab_switch` によって変化しない。

## テストシーム

`tests/test_main.lua` は `ya.sync`、`ya.notify`、`ya.emit`、`fs.cha`、`Command`、`Child`、`Url` をモックする。以下を検証する。

- ファイル・フォルダ、空入力とリンク名変更、入力キャンセル、不正なリンク名、パス引数、選択優先、アクティブタブ反転、refresh、反対側ペインを更新するtab_switch往復、コマンドのstdout/stderr抑制
- 2タブ以外、複数選択、対象なし、特殊ファイル、壊れたリンク、属性取得失敗
- 既存 destination を含むリンクコマンドの起動エラー、waitエラー、非0終了

## 互換性と運用

Yaziの公開Lua APIと `split-tabs.yazi` の2タブモデルに加え、WindowsのファイルリンクではScoop `sudo.cmd` の存在が実行環境の前提である。Git Bashでは `cmd.exe`/`mklink`、WSL/Linux/macOSでは `ln` を使う。実Yazi UI、UAC確認、権限、実ファイルシステムのリンク作成はモックテストでは保証しない。
