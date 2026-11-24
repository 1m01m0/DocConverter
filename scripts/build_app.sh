#!/bin/bash
# 构建 DocConverter.app（含命令行工具 docconv），输出到 dist/
# 用法：scripts/build_app.sh            # Apple 芯片 + Intel 通用版
#       NATIVE=1 scripts/build_app.sh    # 只构建本机架构（更快）
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="DocConverter"
DISPLAY_NAME="Doc Converter"   # 英文是默认语言；其他语言的名称写在各 .lproj/InfoPlist.strings 里
LANGS=(en zh-Hans zh-Hant ja ko fr de es)
BUNDLE_ID="local.docconverter.app"
VERSION="1.1.0"
DIST="dist"
APP="$DIST/$APP_NAME.app"

ARCH_FLAGS=(--arch arm64 --arch x86_64)
if [[ "${NATIVE:-0}" == "1" ]]; then ARCH_FLAGS=(); fi

echo "▸ 编译（release）…"
swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --product DocConverterApp
swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --product docconv
BIN_DIR="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

echo "▸ 组装 $APP …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/DocConverterApp" "$APP/Contents/MacOS/$APP_NAME"
cp "$BIN_DIR/docconv" "$APP/Contents/MacOS/docconv"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# 图标
ICON_TMP="$(mktemp -d)"
swift scripts/make_icon.swift "$ICON_TMP/icon_1024.png" >/dev/null
ICONSET="$ICON_TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$ICON_TMP/icon_1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d "$ICON_TMP/icon_1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICON_TMP"

# 每种界面语言一个 .lproj：App 名称和系统权限提示的翻译由 docconv 从同一份文字表生成
for l in "${LANGS[@]}"; do
  mkdir -p "$APP/Contents/Resources/$l.lproj"
  "$BIN_DIR/docconv" --infoplist-strings "$l" > "$APP/Contents/Resources/$l.lproj/InfoPlist.strings"
  plutil -lint "$APP/Contents/Resources/$l.lproj/InfoPlist.strings" >/dev/null
done
LOCALIZATIONS=$(printf '    <string>%s</string>\n' "${LANGS[@]}")

doc_type() { # 名称 UTI...
  local name="$1"; shift
  echo "    <dict><key>CFBundleTypeName</key><string>$name</string><key>CFBundleTypeRole</key><string>Viewer</string><key>LSHandlerRank</key><string>Alternate</string><key>LSItemContentTypes</key><array>"
  for u in "$@"; do echo "      <string>$u</string>"; done
  echo "    </array></dict>"
}

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key>
  <array>
$LOCALIZATIONS
  </array>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$DISPLAY_NAME</string>
  <key>CFBundleDisplayName</key><string>$DISPLAY_NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>LSHasLocalizedDisplayName</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>DocConverter</string>
  <key>NSDesktopFolderUsageDescription</key><string>Reads the files you choose and saves the converted files next to them.</string>
  <key>NSDocumentsFolderUsageDescription</key><string>Reads the files you choose and saves the converted files next to them.</string>
  <key>NSDownloadsFolderUsageDescription</key><string>Reads the files you choose and saves the converted files next to them.</string>
  <key>NSRemovableVolumesUsageDescription</key><string>Reads and saves files on removable drives.</string>
  <key>NSNetworkVolumesUsageDescription</key><string>Reads and saves files on network drives.</string>
  <key>CFBundleDocumentTypes</key>
  <array>
$(doc_type "PDF" com.adobe.pdf)
$(doc_type "Word" org.openxmlformats.wordprocessingml.document com.microsoft.word.doc)
$(doc_type "PowerPoint" org.openxmlformats.presentationml.presentation)
$(doc_type "Excel" org.openxmlformats.spreadsheetml.sheet)
$(doc_type "Markdown" net.daringfireball.markdown)
$(doc_type "Text" public.html public.plain-text public.rtf public.json public.comma-separated-values-text public.tab-separated-values-text)
$(doc_type "OpenDocument" org.oasis-open.opendocument.text)
$(doc_type "EPUB" org.idpf.epub-container)
$(doc_type "Image" public.png public.jpeg)
  </array>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null

echo "▸ 签名（ad-hoc）…"
codesign --force --sign - "$APP/Contents/MacOS/docconv"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"

echo "▸ 打包 zip …"
rm -f "$DIST/$APP_NAME.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/$APP_NAME.zip"

echo "✓ 完成：$APP"
echo "  命令行工具：$APP/Contents/MacOS/docconv"
lipo -archs "$APP/Contents/MacOS/$APP_NAME" | sed 's/^/  架构：/'
