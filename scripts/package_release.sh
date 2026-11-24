#!/bin/bash
# 打包发布文件（先运行 scripts/build_app.sh）：
#   dist/DocConverter-<版本>-macOS.zip   App + 各语言 README + 截图
#   dist/DocConverter-<版本>-source.zip  完整源码（不含 .build、dist）
set -euo pipefail
cd "$(dirname "$0")/.."
APP="dist/DocConverter.app"
[ -d "$APP" ] || { echo "请先运行 scripts/build_app.sh"; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
NAME="DocConverter-$VERSION"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/$NAME/docs"
ditto "$APP" "$STAGE/$NAME/DocConverter.app"
cp README*.md "$STAGE/$NAME/"
cp docs/screenshot-*.png "$STAGE/$NAME/docs/"
rm -f "dist/$NAME-macOS.zip"
ditto -c -k --sequesterRsrc --keepParent "$STAGE/$NAME" "dist/$NAME-macOS.zip"

rm -f "dist/$NAME-source.zip"
SRC="$STAGE/src/$NAME"; mkdir -p "$SRC"
for item in Package.swift README*.md .gitignore Sources scripts Tests docs; do cp -R "$item" "$SRC/"; done
find "$SRC" -name .DS_Store -delete
(cd "$STAGE/src" && zip -qr -X "$OLDPWD/dist/$NAME-source.zip" "$NAME")

echo "✓ dist/$NAME-macOS.zip  ($(du -h "dist/$NAME-macOS.zip" | cut -f1))"
echo "✓ dist/$NAME-source.zip ($(du -h "dist/$NAME-source.zip" | cut -f1))"
