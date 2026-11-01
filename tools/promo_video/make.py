#!/usr/bin/env python3
"""Fitingo の 30 秒紹介動画（1080x1920・30fps・縦長）を作る。

素材:
  - docs/appstore_screenshots/0N_*.png（App Store 用の紹介画像、tools/appstore_screenshots/make.py）
  - ios/kfit/Videos/fitingo_mv_*.mp4（マスコットの筋トレ動画 1280x720。末尾約1秒のロゴカットは使わない）
出力: docs/promo/fitingo_promo_30s.mp4（音声なし）
使い方: python3 tools/promo_video/make.py   （ffmpeg と Pillow が必要）
"""
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
SLIDES = ROOT / "docs" / "appstore_screenshots"
VIDEOS = ROOT / "ios" / "kfit" / "Videos"
OUT = ROOT / "docs" / "promo" / "fitingo_promo_30s.mp4"
W, H, FPS = 1080, 1920, 30
FADE = 0.4

FONT_HEAVY = "/System/Library/Fonts/ヒラギノ角ゴシック W8.ttc"
FONT_BOLD = "/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc"

# (種類, 素材, 長さ秒, 開始秒 or None, 文字)
# 合計 = 長さの和 - FADE × (区間数 - 1) = 30 秒
TIMELINE = [
    ("clip", "fitingo_mv_squat.mp4", 4.0, 0.3, ("Fitingo", "90秒から、今度こそ続く")),
    ("slide", "01_spiral.png", 3.8, None, None),
    ("clip", "fitingo_mv_pushups.mp4", 2.2, 2.0, ("腕立て伏せ", "お手本と一緒に、正しいフォームで")),
    ("slide", "02_training.png", 3.8, None, None),
    ("clip", "fitingo_mv_lunge.mp4", 2.2, 2.0, ("ランジ", "")),
    ("slide", "03_food.png", 3.8, None, None),
    ("slide", "04_mind.png", 3.8, None, None),
    ("clip", "fitingo_mv_burpee.mp4", 2.2, 3.0, ("バーピー", "")),
    ("slide", "05_streak.png", 3.8, None, None),
    ("clip", "fitingo_mv_squat.mp4", 4.0, 5.0, ("今日から、はじめよう", "Apple Watch 対応 · Apple Health 連携")),
]


def text_overlay(path, title, sub, big):
    """動画の上に重ねる文字（下部に暗いグラデーション + 白文字）"""
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    top = H - 700
    for y in range(top, H):  # 下に向かって暗く
        a = int(200 * (y - top) / (H - top))
        d.line([(0, y), (W, y)], fill=(0, 0, 0, a))
    size = 150 if big else 110
    ft = ImageFont.truetype(FONT_HEAVY, size)
    while d.textlength(title, font=ft) > W - 120 and size > 60:  # 画面幅に収める
        size -= 4
        ft = ImageFont.truetype(FONT_HEAVY, size)
    fs = ImageFont.truetype(FONT_BOLD, 52)
    y = H - (470 if sub else 360)
    d.text((W // 2, y), title, font=ft, fill="white", anchor="mm", stroke_width=4, stroke_fill=(0, 0, 0, 120))
    if sub:
        d.text((W // 2, y + 150), sub, font=fs, fill="white", anchor="mm")
    img.save(path)


def run(cmd):
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)


def make_clip(src, start, dur, overlay, out):
    # 背景: 同じ動画を拡大してぼかし / 前景: 横幅いっぱい（動き全体が見えるように）
    fc = (
        f"[0:v]fps={FPS},split[a][b];"
        f"[a]scale=-2:{H}:flags=lanczos,crop={W}:{H},boxblur=28:4,eq=brightness=-0.12[bg];"
        f"[b]scale={W}:-2:flags=lanczos[fg];"
        f"[bg][fg]overlay=0:(H-h)/2-160[v];"
        f"[v][1:v]overlay=0:0,setsar=1,format=yuv420p"
    )
    run(["ffmpeg", "-y", "-ss", str(start), "-t", str(dur), "-i", str(VIDEOS / src),
         "-loop", "1", "-t", str(dur), "-i", str(overlay),
         "-filter_complex", fc, "-an", "-r", str(FPS),
         "-c:v", "libx264", "-crf", "12", "-preset", "slow", str(out)])


def make_slide(src, dur, out):
    # 紹介画像を横幅に合わせ、見出し → 画面 → タグへゆっくり縦にパンする
    pan = f"(ih-oh)*clip((t-0.5)/({dur}-1.1),0,1)"
    run(["ffmpeg", "-y", "-loop", "1", "-t", str(dur), "-framerate", str(FPS), "-i", str(SLIDES / src),
         "-vf", f"scale={W}:-2:flags=lanczos,crop={W}:{H}:0:'{pan}',setsar=1,format=yuv420p",
         "-an", "-r", str(FPS), "-c:v", "libx264", "-crf", "12", "-preset", "slow", str(out)])


def main():
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        segs, durs = [], []
        for i, (kind, src, dur, start, text) in enumerate(TIMELINE):
            seg = tmp / f"seg{i:02d}.mp4"
            if kind == "clip":
                ov = tmp / f"ov{i:02d}.png"
                text_overlay(ov, text[0], text[1], big=(i == 0))
                make_clip(src, start, dur, ov, seg)
            else:
                make_slide(src, dur, seg)
            segs.append(seg)
            durs.append(dur)
            print(f"  {i + 1}/{len(TIMELINE)} {src}")

        # クロスフェードでつなぐ
        inputs = sum([["-i", str(s)] for s in segs], [])
        parts, prev, offset = [], "0:v", 0.0
        for k in range(1, len(segs)):
            offset += durs[k - 1] - FADE
            label = f"x{k}"
            parts.append(f"[{prev}][{k}:v]xfade=transition=fade:duration={FADE}:offset={offset:.3f}[{label}]")
            prev = label
        run(["ffmpeg", "-y", *inputs, "-filter_complex", ";".join(parts), "-map", f"[{prev}]",
             "-an", "-r", str(FPS), "-c:v", "libx264", "-profile:v", "high", "-crf", "16",
             "-preset", "slow", "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(OUT)])
    print(f"出力: {OUT}")


if __name__ == "__main__":
    main()
