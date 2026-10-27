#!/usr/bin/env bash
# Overlay Fitin files from this folder onto a muse-gadget-sdk checkout.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
SDK="${1:-$ROOT/../../muse-gadget-sdk}"
SRC="$ROOT/firmware"

if [[ ! -d "$SDK/esp32/components/muse" ]]; then
  echo "usage: $0 /path/to/muse-gadget-sdk" >&2
  exit 1
fi

rsync -a "$SRC/" "$SDK/"
echo "overlaid $SRC onto $SDK"
