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
5. source URLの `name` と destination タブの `current.cwd` を使い、`current.cwd:join(name)` で destination URLを構成する。

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

ファイルの場合は `/J` を省略する。

実装では `nil` を配列要素に残さず、フォルダの場合だけ `/J` を追加する。`mklink` の引数順は `link target` なので、destinationを先に渡す。destinationの存在確認を先に行うと競合窓が増えるため、上書きしない各コマンドの失敗を正とする。終了成功時だけ `ya.emit("refresh", {})` を発行し、完了通知を表示する。起動失敗、wait失敗、非0終了は詳細を通知する。

## テストシーム

`tests/test_main.lua` は `ya.sync`、`ya.notify`、`ya.emit`、`fs.cha`、`Command`、`Child`、`Url` をモックする。以下を検証する。

- ファイル・フォルダ、パス引数、選択優先、アクティブタブ反転、refresh
- 2タブ以外、複数選択、対象なし、特殊ファイル、壊れたリンク、属性取得失敗
- 既存 destination を含むリンクコマンドの起動エラー、waitエラー、非0終了

## 互換性と運用

Yaziの公開Lua APIと `split-tabs.yazi` の2タブモデルだけに依存する。Git Bashでは `cmd.exe`/`mklink`、WSL/Linux/macOSでは `ln` の存在が実行環境の前提である。Windowsのシンボリックリンク権限またはジャンクション作成権限もREADMEに明記する。実Yazi UI、権限、実ファイルシステムのリンク作成はモックテストでは保証しない。
