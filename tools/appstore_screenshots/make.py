#!/usr/bin/env python3
"""App Store 用の紹介画像（スクリーンショット + キャッチコピー）を 5 枚作る。

入力: docs/screenshots/ の実機スクリーンショット
出力: docs/appstore_screenshots/0N_*.png（1320x2868 = iPhone 6.9 インチ）
      docs/appstore_screenshots/overview.png（確認用の一覧）
使い方: python3 tools/appstore_screenshots/make.py   （Pillow が必要）
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
SHOTS = ROOT / "docs" / "screenshots"
OUT = ROOT / "docs" / "appstore_screenshots"
W, H = 1320, 2868

FONT_HEAVY = "/System/Library/Fonts/ヒラギノ角ゴシック W8.ttc"
FONT_BOLD = "/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc"

# (ファイル名, スクリーンショット, 見出し, 説明, 背景の上色, 背景の下色)
SLIDES = [
    ("01_spiral", "main/IMG_3498.jpg",
     "今日の習慣が\nひと目でわかる", "運動・食事・睡眠・学び。全部の目標を\n1枚のスパイラルで達成率に",
     (88, 204, 2), (46, 160, 60)),
    ("02_training", ("main/IMG_3501.jpg", (40, 460, 1166, 1260),
                     # Apple Watch でのカウント画面を下に並べる
                     ["watch/incoming-4B24B149-215E-4EB7-A5B2-EF5961218BDD.PNG",
                      "watch/incoming-7E630B2D-205F-436D-9002-EA2441C4E805.PNG"]),
     "Apple Watch /\nモーションセンサーで\nカウント", "iPhone と Apple Watch のセンサーが\n腕立て・スクワット・腹筋を自動で記録",
     (28, 176, 246), (20, 120, 200)),
    ("03_food", "main/IMG_3504.jpg",
     "撮るだけで\nAIが栄養分析", "食事の写真から、カロリーとPFCを推定。\nApple Health にもそのまま保存",
     (255, 150, 0), (235, 100, 30)),
    ("04_mind", "mind/IMG_3516.jpg",
     "ストレスと睡眠も\n見える化", "心拍変動（HRV）から今の状態を確認。\n1分瞑想・3分ストレッチで整える",
     (140, 110, 240), (90, 70, 200)),
    ("05_streak", "main/IMG_3507.jpg",
     "90秒から、\n今度こそ続く", "ポイントと連続記録、90日チャレンジ。\n小さな一歩が習慣に変わる",
     (88, 204, 2), (255, 170, 0)),
]


def gradient(top, bottom):
    img = Image.new("RGB", (W, H), top)
    d = ImageDraw.Draw(img)
    for y in range(H):
        t = y / (H - 1)
        d.line([(0, y), (W, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)))
    return img


def rounded(im, radius):
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, im.width - 1, im.height - 1], radius=radius, fill=255)
    out = Image.new("RGBA", im.size)
    out.paste(im, (0, 0), mask)
    return out


def draw_centered(d, y, text, font, fill, spacing):
    for line in text.split("\n"):
        d.text((W // 2, y), line, font=font, fill=fill, anchor="mt")
        y += font.size + spacing
    return y


CHIPS = ["Apple Watch 対応", "Apple Health 連携", "無料ではじめられる"]


def draw_chips(img, y):
    """半透明のタグを重ねる（ImageDraw は半透明を合成しないため別レイヤーで描いて合成）"""
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    font = ImageFont.truetype(FONT_BOLD, 36)
    pad, gap = 28, 18
    widths = [d.textlength(c, font=font) + pad * 2 for c in CHIPS]
    x = (W - (sum(widths) + gap * (len(CHIPS) - 1))) / 2
    for c, w in zip(CHIPS, widths):
        d.rounded_rectangle([x, y, x + w, y + 84], radius=42, fill=(255, 255, 255, 60),
                            outline=(255, 255, 255, 200), width=3)
        d.text((x + w / 2, y + 42), c, font=font, fill="white", anchor="mm")
        x += w + gap
    return Image.alpha_composite(img, layer)


def paste_watches(img, files, y):
    """Apple Watch の画面を黒い角丸の枠に入れて横に並べる"""
    ww, gap, frame = 420, 70, 22
    x = (W - (ww * len(files) + gap * (len(files) - 1))) // 2
    for f in files:
        src = Image.open(SHOTS / f).convert("RGB")
        wh = int(src.height * ww / src.width)
        face = rounded(src.resize((ww, wh), Image.LANCZOS), 70)
        body = Image.new("RGBA", img.size, (0, 0, 0, 0))
        ImageDraw.Draw(body).rounded_rectangle([x - frame, y - frame, x + ww + frame, y + wh + frame],
                                               radius=90, fill=(28, 28, 30, 255))
        img = Image.alpha_composite(img, body)
        img.paste(face, (x, y), face)
        x += ww + gap
    return img


def make_slide(name, shot, title, sub, top, bottom):
    img = gradient(top, bottom).convert("RGBA")
    d = ImageDraw.Draw(img)
    # 見出し・説明
    three_lines = title.count("\n") >= 2
    y = draw_centered(d, 150 if three_lines else 170, title,
                      ImageFont.truetype(FONT_HEAVY, 100 if three_lines else 118), "white", 24)
    text_bottom = draw_centered(d, y + 40, sub, ImageFont.truetype(FONT_BOLD, 50), (255, 255, 255, 235), 22)

    # スクリーンショット（角丸 + 影）
    crop, watches = None, []
    if isinstance(shot, tuple):  # (ファイル, 切り出し範囲, Apple Watch の画面)
        shot, crop, watches = shot
    src = Image.open(SHOTS / shot).convert("RGB")
    if crop:
        src = src.crop(crop)
    card_w = 1160
    card_h = int(src.height * card_w / src.width)
    max_h = H - 820 - 330
    if card_h > max_h:  # 縦長すぎる場合は上部を使う
        src = src.crop((0, 0, src.width, int(src.width * max_h / card_w)))
        card_h = max_h
    card = rounded(src.resize((card_w, card_h), Image.LANCZOS), 56)
    # 画面の高さが足りない場合は、空いた領域の中央に置く
    x0 = (W - card_w) // 2
    top = max(820, text_bottom + 70)  # 見出しが長い場合は画面を下げる
    y0 = top if watches else top + max(0, (max_h - card_h) // 2)
    shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([x0 + 10, y0 + 30, x0 + card_w + 10, y0 + card_h + 30],
                                             radius=56, fill=(0, 0, 0, 90))
    img = Image.alpha_composite(img, shadow.filter(ImageFilter.GaussianBlur(28)))
    border = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(border).rounded_rectangle([x0 - 14, y0 - 14, x0 + card_w + 14, y0 + card_h + 14],
                                             radius=68, fill=(255, 255, 255, 255))
    img = Image.alpha_composite(img, border)
    img.paste(card, (x0, y0), card)
    if watches:
        img = paste_watches(img, watches, y0 + card_h + 90)
    img = draw_chips(img, H - 210)
    out = img.convert("RGB")
    out.save(OUT / f"{name}.png", optimize=True)
    return out


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    slides = [make_slide(*s) for s in SLIDES]
    tw = 330
    th = int(H * tw / W)
    sheet = Image.new("RGB", (len(slides) * (tw + 16) + 16, th + 32), (240, 240, 240))
    for i, s in enumerate(slides):
        sheet.paste(s.resize((tw, th), Image.LANCZOS), (16 + i * (tw + 16), 16))
    sheet.save(OUT / "overview.png", optimize=True)
    print(f"出力: {OUT}")


if __name__ == "__main__":
    main()
