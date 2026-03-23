# VideoTimeSync (remylog labs)

Final Cut Pro等で書き出した動画の日時を、元素材と同期させるmacOS用ツールです。
Finderの作成日・変更日だけでなく、写真アプリが参照する内部メタデータ(QuickTimeタグ)も一括で修正します。

## 特徴

- 🍎 **Mac風デザイン**: CustomTkinterを使用したモダンなUI
- ⚡ **一括同期**: ファイルシステムと内部メタデータを同時に修正
- 🖥️ **レスポンシブ**: ウィンドウサイズに合わせてUIがオートスケール

## 必要条件

- macOS
- [exiftool](https://exiftool.org/) (`brew install exiftool` でインストール可能)

## 使い方

1. `main.py` を実行するか、ビルドしたアプリを起動します。
2. 「元素材」と「書き出し後動画」を選択します。
3. 「日時情報を同期実行」をクリックして完了！

## 開発環境

- Python 3.12+
- CustomTkinter
