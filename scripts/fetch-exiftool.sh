#!/bin/bash
# exiftool（Perlスクリプト版）をダウンロードし、アプリに同梱する Resources/exiftool を作る。
# 使い方:  ./scripts/fetch-exiftool.sh [バージョン]
# 例:      ./scripts/fetch-exiftool.sh 13.59
set -euo pipefail

VERSION="${1:-13.59}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Resources/exiftool"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "exiftool ${VERSION} を取得します..."
git clone --quiet --depth 1 --branch "$VERSION" https://github.com/exiftool/exiftool.git "$WORK/exiftool"

rm -rf "$DEST"
mkdir -p "$DEST"
cp "$WORK/exiftool/exiftool" "$DEST/exiftool"
cp -R "$WORK/exiftool/lib" "$DEST/lib"
cp "$WORK/exiftool/LICENSE" "$DEST/LICENSE"
chmod +x "$DEST/exiftool"

echo "完了: $DEST"
/usr/bin/perl "$DEST/exiftool" -ver
