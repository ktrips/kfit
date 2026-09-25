#!/bin/bash
# generate.py の出力（out/stage*_*.png、マゼンタ背景）を M5 用に加工する。
#   - マゼンタを透過に切り抜き、160x180 に収まるよう縮小 → m5/stage{N}_{expr}.png
#   - 全ステージを並べた確認用の一覧 → contact_sheet.png（同じキャラに見えるか確認する用）
# 必要: ffmpeg
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p m5

shopt -s nullglob
files=(out/stage*_*.png)
[ ${#files[@]} -eq 0 ] && { echo "out/ に画像がありません（先に generate.py を実行）"; exit 1; }

for f in "${files[@]}"; do
  name=$(basename "$f")
  ffmpeg -y -loglevel error -i "$f" \
    -vf "colorkey=0xFF00FF:0.35:0.15,scale=160:180:force_original_aspect_ratio=decrease,pad=160:180:(ow-iw)/2:(oh-ih):color=0x00000000,format=rgba" \
    "m5/$name"
  echo "m5/$name"
done

# 一覧: 各画像を 256px にして横 4 列（表情）× 縦（ステージ）
ffmpeg -y -loglevel error -pattern_type glob -i 'out/stage*_*.png' \
  -vf "scale=256:256,tile=4x6:padding=4:color=white" -frames:v 1 contact_sheet.png
echo "contact_sheet.png"
