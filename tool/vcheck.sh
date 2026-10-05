#!/bin/bash
# 视觉自查循环：构建 → 卸载旧包 → 装新包 → 启动 → 截图
# 用法: ./tool/vcheck.sh <截图名> [更多截图指令...]
set -e
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
DEV=${ETSH_DEV:-127.0.0.1:7555}
PKG=com.eets.e_ets_helper

flutter build apk --debug 2>&1 | grep -E "Built|rror" | tail -2
adb -s "$DEV" uninstall "$PKG" >/dev/null 2>&1 || true
adb -s "$DEV" install build/app/outputs/flutter-apk/app-debug.apk 2>&1 | tail -1
adb -s "$DEV" shell am start -n "$PKG/.MainActivity" >/dev/null 2>&1
sleep 11

OUT="C:/Users/Admin/AppData/Local/Temp"
NAME=${1:-shot}
adb -s "$DEV" shell screencap -p /sdcard/s.png
adb -s "$DEV" pull /sdcard/s.png "$OUT/$NAME.png" >/dev/null
echo "shot -> $OUT/$NAME.png"

shift || true
for arg in "$@"; do
  case "$arg" in
    tap:*) xy=${arg#tap:}; adb -s "$DEV" shell input tap ${xy//,/ }; sleep 3 ;;
    swipe:*) xy=${arg#swipe:}; adb -s "$DEV" shell input swipe ${xy//,/ }; sleep 2 ;;
    wait:*) sleep "${arg#wait:}" ;;
  esac
done