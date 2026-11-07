#!/bin/zsh
set -eu
TASK_DIR="${0:A:h:h}"
GODOT_BIN="${GODOT_BIN:-}"
if [[ -z "$GODOT_BIN" ]]; then
  for candidate in /Applications/Godot.app/Contents/MacOS/Godot "$HOME/Downloads/Godot.app/Contents/MacOS/Godot"; do
    if [[ -x "$candidate" ]]; then GODOT_BIN="$candidate"; break; fi
  done
fi
if [[ -z "$GODOT_BIN" ]]; then
  GODOT_BIN="$(command -v godot || command -v godot4 || true)"
fi
if [[ -z "$GODOT_BIN" || ! -x "$GODOT_BIN" ]]; then
  print '未找到 Godot 4。请用 Godot 导入项目根目录的 project.godot，或设置 GODOT_BIN 环境变量。'
  read '?按回车关闭。'
  exit 1
fi
exec "$GODOT_BIN" --path "$TASK_DIR" "$@"
