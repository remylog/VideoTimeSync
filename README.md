# VideoTimeSync (remylog labs)

Windows などで録画した動画を Mac でトリミングして保存すると、ファイルの日時が「保存した時刻」に変わってしまいます。
このアプリは、編集後の動画の日時を、元の録画ファイルの日時に戻す macOS 用ツールです。

## 何を書き換えるか

| 対象 | 内容 |
| --- | --- |
| 内部メタデータ | QuickTime の日時タグ（CreateDate / ModifyDate / Track / Media）を元ファイルからコピー。写真アプリはここを参照します |
| Finder の作成日・更新日 | 元ファイルの値に設定 |

内部タグは UTC のままコピーするため、タイムゾーンのずれは起きません。
元ファイルにタグがない場合だけ、更新日時を UTC に変換して書き込みます。

処理のあとで、書き込んだ値を読み直して一致を検証し、一致しなければ失敗として表示します。

## 使い方

1. 元録画と編集後の動画を、ウィンドウへドロップします。まとめてでも、別々にでも構いません。
2. ファイル名で元と先が自動的に振り分けられ、ペアになります。
   - 編集後のファイル名の末尾（接尾辞、初期値 `_ex`）で判定します。`Video.mp4` は元、`Video_ex.mp4` は先です。
   - 大文字・小文字は区別しません。拡張子が違っていても、名前が対応していればペアになります。
   - 相手がまだ見つからないファイルは片側だけの行として残り、あとから相手をドロップすると自動で1行にまとまります。
3. 「同期を実行」を押します（Command + Return でも実行できます）。

- 接尾辞を変えたときは、「未対応を再ペアリング」を押すと組み合わせ直せます。
- 行ごとに、元と先を直接ドロップして差し替えられます。入れ替えボタンもあります。
- 「実行前にバックアップ」をオンにすると、先ファイルを同じフォルダの `VideoTimeSync_Backup` にコピーしてから書き換えます。
- 対応形式は mp4 / mov / m4v です。

## ビルド方法

必要なもの: macOS 14 以降、Xcode 15 以降、[XcodeGen](https://github.com/yonaskolb/XcodeGen)

```
brew install xcodegen
./scripts/fetch-exiftool.sh   # exiftool をアプリに同梱するために取得
xcodegen generate             # VideoTimeSync.xcodeproj を生成
open VideoTimeSync.xcodeproj  # Xcode で開いて Run
```

`fetch-exiftool.sh` を実行しない場合、アプリは Homebrew の exiftool（`brew install exiftool`）を探して使います。

## 注意

- 同梱の exiftool は Perl スクリプトで、macOS 標準の `/usr/bin/perl` で動かします。
- App Sandbox は無効です（外部ボリュームの動画を自由に読み書きするため）。App Store 配布には向きません。
- リリースは Developer ID の公証なし（アドホック署名）です。初回起動時は右クリックから「開く」を選んでください。

## 開発環境

- Swift 5 / SwiftUI
- macOS 14.0+

## ライセンス

同梱する ExifTool は Artistic License / GPL でライセンスされています（`Resources/exiftool/LICENSE`）。
