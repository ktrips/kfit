#!/usr/bin/env bash
# Copy Fitin overlay files from a local muse-gadget-sdk tree into this folder.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
SDK="${1:-$ROOT/../../muse-gadget-sdk}"
DEST="$ROOT/firmware"

if [[ ! -f "$SDK/esp32/components/muse/muse_fit.c" ]]; then
  echo "usage: $0 /path/to/muse-gadget-sdk" >&2
  echo "expected Fitin files in $SDK" >&2
  exit 1
fi

files=(
  esp32/avatar/muse_pixel.c
  esp32/components/muse/CMakeLists.txt
  esp32/components/muse/boards/board_m5stack_cores3.c
  esp32/components/muse/boards/bmi270_config.inl
  esp32/components/muse/muse_app.c
  esp32/components/muse/muse_audio.c
  esp32/components/muse/muse_audio.h
  esp32/components/muse/muse_pixel.h
  esp32/components/muse/muse_settings.c
  esp32/components/muse/muse_settings.h
  esp32/components/muse/muse_settings_ui.c
  esp32/components/muse/muse_state.c
  esp32/components/muse/muse_state.h
  esp32/components/muse/muse_ui.c
  esp32/components/muse/muse_activity_ui.c
  esp32/components/muse/muse_activity_ui.h
  esp32/components/muse/muse_cam.c
  esp32/components/muse/muse_cam.h
  esp32/components/muse/muse_chat.h
  esp32/components/muse/muse_chat_session.cpp
  esp32/components/muse/muse_voice.c
  esp32/components/muse/muse_voice.h
  esp32/devices/sdkconfig.muse-m5stack-cores3
  esp32/components/muse/muse_clock.c
  esp32/components/muse/muse_clock.h
  esp32/components/muse/muse_fit.c
  esp32/components/muse/muse_fit.h
  esp32/components/muse/muse_hr.c
  esp32/components/muse/muse_hr.h
  esp32/components/muse/muse_squat.c
  esp32/components/muse/muse_squat.h
  esp32/components/muse/muse_timer.c
  esp32/components/muse/muse_timer.h
)

for f in "${files[@]}"; do
  mkdir -p "$DEST/$(dirname "$f")"
  cp "$SDK/$f" "$DEST/$f"
done
echo "synced ${#files[@]} files from $SDK -> $DEST"
