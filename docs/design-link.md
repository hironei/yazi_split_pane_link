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

ファイルの場合は `%USERPROFILE%\scoop\shims\sudo.cmd` を経由して、次のようにUAC昇格する。destinationとsourceを直接引数として渡さず、`mklink` 呼び出しを書いた一時 `.cmd` スクリプトを`%TEMP%`（`%TMP%`）に生成し、そのスクリプトパス1つだけをsudo.cmdに渡す。

```
Command("cmd.exe")
  :arg {
    "/d", "/c", sudo_path,
    "cmd.exe", "/d", "/c", script_path,
  }
```

一時スクリプトの内容は次の形（destination/sourceは常にダブルクォートで囲む）。

```
@echo off
mklink "destination" "source" >nul 2>&1
exit /b %errorlevel%
```

一時スクリプト経由にしているのは、Scoopの`sudo.cmd`（gsudo系ツール）が引数を1本の文字列に再結合し、その文字列を昇格プロセス・PowerShellをまたいで複数回再パースする実装だからである。実機検証で、`mklink destination source` を素の引数リストとしてsudo.cmd経由に渡すと、Windowsパス（例: `C:\Users\...`）の一部が `mklink` に対する不正なスイッチ（例: `/Users`）として解釈され、リンクが作成されないままYaziには成功と表示される事象を確認した。渡す引数を一時スクリプトのパス1つに減らすことで、この多段再パースに起因する破損の余地をなくしている。加えて、`mklink` 自身の標準出力をスクリプト内で `>nul 2>&1` により明示的に抑制する。sudo.cmd（gsudo系ツール）は昇格後のプロセスをWin32の `AttachConsole` で元のコンソールへ直接アタッチし直すため、`Command:stdout(Command.NULL):stderr(Command.NULL)`（後述）だけでは`mklink`自身の出力を抑止できない。

`sudo.cmd` が存在しない、`%TEMP%`/`%TMP%` が取得できない、一時スクリプトの書き込みに失敗した場合は `mklink` を起動せず通知する。一時スクリプトは `child:wait()` 完了後（成功・失敗を問わず）に `os.remove` で削除する。フォルダではUAC昇格も一時スクリプトも使わない。

実装では `nil` を配列要素に残さず、フォルダの場合だけ `/J` を追加する。`mklink` の引数順は `link target` なので、destinationを先に渡す。destinationの存在確認を先に行うと競合窓が増えるため、上書きしない各コマンドの失敗を正とする。入力キャンセルは作成せず終了し、不正なリンク名、`sudo.cmd` の欠落、一時スクリプトの作成失敗、起動失敗、UACキャンセル、wait失敗、非0終了は通知する。

`ln`/`mklink`（フォルダの`/J`）の `Command` にはそれぞれ `:stdout(Command.NULL):stderr(Command.NULL)` を指定する。指定しないとWindowsでは子プロセスの標準出力（`mklink` の完了メッセージ等）がYaziの端末画面バッファへ直接書き込まれ、TUIの描画と重なって残像として残る。ファイルリンク（sudo.cmd経由）の場合はこれに加えて上記の一時スクリプト内の出力抑制が必要になる。

終了成功時は `ya.emit("refresh", {})` を発行したうえで、`ya.emit("tab_switch", { other_index })` → `ya.emit("tab_switch", { active_index })` の順で発行し、完了通知を表示する。YaziのMgrコマンド（`refresh`/`watch`）は常にアクティブタブだけを対象にし、ファイルシステム監視によるリアクティブな `update_files` も非アクティブタブへは配信されない。そのため、反対側ペイン（非アクティブタブ）が作成直後のリンクを表示するには、`tab_switch` がその内部で対象タブに対して `refresh` を実行する仕組みを利用し、反対側タブへ一旦切り替えてから元のアクティブタブへ戻す。タブ数が2以外（作成待機中にタブが増減した場合）はこの往復をスキップし、アクティブタブの `refresh` のみ行う。選択状態・カーソル・各タブの `current.cwd` は `tab_switch` によって変化しない。

## テストシーム

`tests/test_main.lua` は `ya.sync`、`ya.notify`、`ya.emit`、`fs.cha`、`Command`、`Child`、`Url` をモックする。以下を検証する。

- ファイル・フォルダ、空入力とリンク名変更、入力キャンセル、不正なリンク名、パス引数、選択優先、アクティブタブ反転、refresh、反対側ペインを更新するtab_switch往復、コマンドのstdout/stderr抑制
- ファイルリンクの一時スクリプト生成内容（`mklink`呼び出し・出力抑制・exitコード伝搬）と実行後の削除、`%TEMP%`/`%TMP%`未取得時と書き込み失敗時の通知
- 2タブ以外、複数選択、対象なし、特殊ファイル、壊れたリンク、属性取得失敗
- 既存 destination を含むリンクコマンドの起動エラー、waitエラー、非0終了

## 互換性と運用

Yaziの公開Lua APIと `split-tabs.yazi` の2タブモデルに加え、WindowsのファイルリンクではScoop `sudo.cmd` の存在が実行環境の前提である。Git Bashでは `cmd.exe`/`mklink`、WSL/Linux/macOSでは `ln` を使う。実Yazi UI、UAC確認、権限、実ファイルシステムのリンク作成はモックテストでは保証しない。
