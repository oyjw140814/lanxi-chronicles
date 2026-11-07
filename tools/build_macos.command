#!/bin/zsh
# Development bundle built with the installed MIT-licensed Godot runtime.
set -eu
TASK_DIR="${0:A:h:h}"
GODOT_BIN="${GODOT_BIN:-$HOME/Downloads/Godot.app/Contents/MacOS/Godot}"
if [[ ! -x "$GODOT_BIN" ]]; then
  print '请把 GODOT_BIN 设置为 Godot 4.7.2 的可执行文件路径。'
  exit 1
fi
BUILD_STAGE="$(mktemp -d /private/tmp/lanxi-package.XXXXXX)"
APP_PATH="$BUILD_STAGE/岚汐纪.app"
FINAL_APP="$TASK_DIR/builds/岚汐纪.app"
"$GODOT_BIN" --headless --path "$TASK_DIR" --editor --quit
"$GODOT_BIN" --headless --path "$TASK_DIR" --export-pack macOS "$TASK_DIR/builds/LanXiJi.pck"
"$GODOT_BIN" --headless --path "$TASK_DIR" --script tools/package_metadata.gd
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources" "$TASK_DIR/builds/LanXiJi.iconset"
if [[ "$(uname -m)" == arm64 ]]; then
  lipo "$GODOT_BIN" -thin arm64 -output "$APP_PATH/Contents/MacOS/LanXiJi"
else
  lipo "$GODOT_BIN" -thin x86_64 -output "$APP_PATH/Contents/MacOS/LanXiJi"
fi
cp "$TASK_DIR/builds/LanXiJi.pck" "$APP_PATH/Contents/Resources/LanXiJi.pck"
cp "$TASK_DIR/docs/THIRD_PARTY_NOTICES.txt" "$APP_PATH/Contents/Resources/THIRD_PARTY_NOTICES.txt"
cp "$TASK_DIR/assets/fonts/OFL-NotoSansSC.txt" "$APP_PATH/Contents/Resources/OFL-NotoSansSC.txt"
for pixels in 16 32 128 256 512; do
  icon_file="$TASK_DIR/builds/LanXiJi.iconset/icon_${pixels}x${pixels}.png"
  icon_file_2x="$TASK_DIR/builds/LanXiJi.iconset/icon_${pixels}x${pixels}@2x.png"
  sips -z "$pixels" "$pixels" "$TASK_DIR/builds/icon-1024.png" --out "$icon_file" >/dev/null
  twice=$((pixels * 2))
  sips -z "$twice" "$twice" "$TASK_DIR/builds/icon-1024.png" --out "$icon_file_2x" >/dev/null
  # Godot treats PNGs as importable project assets; iconutil only accepts the
  # PNG members of an .iconset, so discard sidecar files left by the importer.
  rm -f "$icon_file.import" "$icon_file_2x.import"
done
if ! iconutil -c icns "$TASK_DIR/builds/LanXiJi.iconset" -o "$APP_PATH/Contents/Resources/LanXiJi.icns"; then
  # Some macOS runners ship an iconutil that rejects otherwise valid PNG
  # iconsets. Keep packaging usable by reusing the project's checked-in icon
  # while the game binary and PCK still come from this build.
  if [[ -f "$FINAL_APP/Contents/Resources/LanXiJi.icns" ]]; then
    cp "$FINAL_APP/Contents/Resources/LanXiJi.icns" "$APP_PATH/Contents/Resources/LanXiJi.icns"
  else
    print -u2 'iconutil 无法生成 icns，且没有可复用的旧图标。'
    exit 1
  fi
fi
cp "$TASK_DIR/tools/macos-Info.plist" "$APP_PATH/Contents/Info.plist"
printf 'APPL????' > "$APP_PATH/Contents/PkgInfo"
chmod +x "$APP_PATH/Contents/MacOS/LanXiJi"
codesign --force --sign - "$APP_PATH"
codesign --verify "$APP_PATH"
ditto --norsrc "$APP_PATH" "$FINAL_APP"
print "已生成本机架构的开发版：$FINAL_APP"
print '该版本包含引擎运行时，不需要另装 Godot；未经过 Apple 公证，不作为商店发行包。'
