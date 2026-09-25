#!/usr/bin/env python3
"""FitinGO（M5Stack CoreS3）向けのシンプルなキャラクター素材を生成する。

画像生成 AI を使わず、図形だけで描くフラットな版。docs/CHARACTER_STAGES.md の
「体つき・服装・道具・背景・ポーズ・エフェクト」の組み合わせをそのまま反映する。

出力（tools/character_stages/simple/）:
  sprites/stage{N}_{expr}.png  160x180 透過 PNG（6 ステージ × 表情 4 種 = 24 枚）
  bg/stage{N}.png              320x180 背景（6 枚）
  preview/stage{N}.png         320x240 実機画面イメージ（背景 + キャラ + 下部 UI）
  contact_sprites.png / contact_screens.png  確認用の一覧

使い方: python3 tools/character_stages/simple_sprites.py   （Pillow が必要）
"""
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parent / "simple"
S = 4  # 高解像度で描いて縮小（アンチエイリアス）

GREEN, GREEN_D, GREEN_L = (88, 180, 60), (46, 125, 50), (160, 225, 120)
SHIRT_G, SHIRT_D = (30, 110, 58), (20, 80, 40)
ORANGE, WHITE, BLACK, INK = (255, 167, 38), (255, 255, 255), (30, 30, 30), (18, 34, 51)
GOLD, GOLD_D = (255, 205, 60), (200, 150, 20)

NAMES = ["ひよこ", "ビギナー", "アスリート", "マッスル", "ムキムキ", "レジェンド"]
EXPRS = ["sleepy", "calm", "excited", "joy"]


def jp_font(size):
    for p in ["/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc",
              "/System/Library/Fonts/Hiragino Sans GB.ttc",
              "/System/Library/Fonts/Supplemental/Arial Bold.ttf"]:
        if Path(p).exists():
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


class Pen:
    """160x180 の座標で描き、内部では S 倍で描画する。"""

    def __init__(self, w, h):
        self.img = Image.new("RGBA", (w * S, h * S), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.img)

    def ell(self, cx, cy, rx, ry, fill, outline=None, width=0):
        self.d.ellipse([(cx - rx) * S, (cy - ry) * S, (cx + rx) * S, (cy + ry) * S],
                       fill=fill, outline=outline, width=int(width * S))

    def rect(self, x0, y0, x1, y1, fill, r=0, outline=None, width=0):
        self.d.rounded_rectangle([x0 * S, y0 * S, x1 * S, y1 * S], radius=r * S,
                                 fill=fill, outline=outline, width=int(width * S))

    def line(self, pts, fill, width):
        pts = [(x * S, y * S) for x, y in pts]
        self.d.line(pts, fill=fill, width=int(width * S), joint="curve")
        r = width * S / 2
        for x, y in (pts[0], pts[-1]):  # 丸い端
            self.d.ellipse([x - r, y - r, x + r, y + r], fill=fill)

    def poly(self, pts, fill):
        self.d.polygon([(x * S, y * S) for x, y in pts], fill=fill)

    def arc(self, cx, cy, rx, ry, start, end, fill, width):
        self.d.arc([(cx - rx) * S, (cy - ry) * S, (cx + rx) * S, (cy + ry) * S],
                   start, end, fill=fill, width=int(width * S))

    def text(self, xy, s, size, fill, anchor="mm"):
        self.d.text((xy[0] * S, xy[1] * S), s, font=jp_font(int(size * S)), fill=fill, anchor=anchor)

    def star(self, cx, cy, r, fill):
        pts = []
        for i in range(8):
            a = math.pi / 4 * i - math.pi / 2
            rr = r if i % 2 == 0 else r * 0.35
            pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
        self.poly(pts, fill)

    def out(self, w, h):
        return self.img.resize((w, h), Image.LANCZOS)


# ---------------------------------------------------------------- キャラクター

def draw_character(st, expr):
    p = Pen(160, 180)
    rx = 22 + 3.5 * (st - 1)          # 胴の横幅（成長で太くなる）
    arm = 6 + 2.2 * st                # 腕の太さ
    hx = 28 + (2 if st >= 4 else 0)   # 頭の横幅
    cx = 80

    # --- 背面エフェクト
    if st == 3:
        p.ell(cx, 110, 70, 72, (126, 217, 87, 70))
    if st == 5:
        p.ell(cx, 105, 76, 78, (255, 150, 40, 70))
        for i in range(9):
            a = math.pi * (0.08 + 0.84 * i / 8)
            x, y = cx - math.cos(a) * 68, 168 - math.sin(a) * 62
            col = (255, 122, 47, 230) if i % 2 else (255, 201, 60, 230)
            p.poly([(x - 9, y + 16), (x, y - 26), (x + 9, y + 16)], col)
    if st == 6:
        for i in range(14):
            a = 2 * math.pi * i / 14
            p.line([(cx + math.cos(a) * 58, 95 + math.sin(a) * 58),
                    (cx + math.cos(a) * 79, 95 + math.sin(a) * 79)], (255, 213, 74, 200), 3)
        p.ell(cx, 100, 68, 74, (255, 230, 120, 150))

    # --- 道具（地面に置くもの）
    if st in (4, 5):
        plate = 14 if st == 4 else 19
        p.line([(18, 166), (142, 166)], (90, 90, 90), 4)
        for x in (26, 134):
            p.rect(x - 5, 166 - plate, x + 5, 166 + plate, (50, 50, 50), r=2)

    # --- 脚・足
    for s in (-1, 1):
        p.line([(cx + s * rx * 0.42, 140), (cx + s * rx * 0.48, 166)], GREEN_D, 9 + st * 1.4)
        p.ell(cx + s * rx * 0.55, 170, 9 + st * 0.8, 5, ORANGE)

    # --- 胴
    p.ell(cx, 115, rx, 33, GREEN)
    if st == 1:
        p.ell(cx, 122, rx * 0.6, 20, GREEN_L)

    # --- 服装
    if st == 1:     # ロゴなしの白い大きめ T シャツ
        p.rect(cx - rx - 3, 90, cx + rx + 3, 140, (245, 245, 245), r=10)
    elif st == 2:   # 緑の T シャツ + 小さなロゴ
        p.rect(cx - rx - 2, 90, cx + rx + 2, 138, SHIRT_G, r=10)
        p.text((cx, 110), "FITINGO", 6, WHITE)
    else:           # タンクトップ + ショーツ
        trim = GOLD if st == 6 else WHITE
        p.rect(cx - 18, 134, cx + 18, 150, SHIRT_D, r=5, outline=trim, width=1.2)
        p.rect(cx - rx * 0.78, 92, cx + rx * 0.78, 140, SHIRT_G, r=9, outline=trim, width=1.5)
        p.text((cx, 114), "FITINGO", 7 + st * 0.4, WHITE)
        if st == 5:  # トレーニングベルト
            p.rect(cx - rx * 0.8, 132, cx + rx * 0.8, 140, (110, 70, 40), r=2)
            p.rect(cx - 5, 131, cx + 5, 141, (200, 200, 200), r=1)

    # --- 腕（ポーズ）
    def hand(x, y, r=None):
        p.ell(x, y, r or arm * 0.62, r or arm * 0.62, GREEN)

    sh = 96  # 肩の高さ
    if st == 1:     # 手を振る（右腕上げ）+ 左手に水のボトル
        p.line([(cx - rx + 3, sh), (cx - rx - 6, 132)], GREEN, arm)
        p.rect(cx - rx - 12, 124, cx - rx - 2, 146, (120, 200, 255), r=3)
        p.rect(cx - rx - 10, 120, cx - rx - 4, 125, (60, 120, 200), r=1)
        p.line([(cx + rx - 3, sh), (cx + rx + 24, 66)], GREEN, arm)
        hand(cx + rx + 24, 62)
        towel = (120, 190, 240)
        p.rect(cx - 20, 87, cx + 20, 95, towel, r=4)  # 首のタオル
        p.rect(cx + 8, 89, cx + 16, 114, towel, r=3)
    elif st in (2, 3):  # 腕を下ろしてダンベル
        for s in (-1, 1):
            p.line([(cx + s * (rx - 4), sh), (cx + s * (rx + 8), 138)], GREEN, arm)
            hand(cx + s * (rx + 8), 140)
        db = 6 if st == 2 else 9
        x = cx + rx + 8
        p.line([(x - 12, 142), (x + 12, 142)], (90, 90, 90), 3)
        for dx in (-12, 12):
            p.rect(x + dx - 3, 142 - db, x + dx + 3, 142 + db, (60, 60, 60), r=2)
    elif st in (4, 5):  # ダブルバイセップス
        for s in (-1, 1):
            ex = cx + s * (rx + 18)
            p.line([(cx + s * (rx - 6), sh), (ex, 100)], GREEN, arm)
            p.line([(ex, 100), (ex - s * 4, 62)], GREEN, arm * 0.85)
            p.ell(cx + s * (rx + 8), 90, arm * 0.8, arm * 0.7, GREEN)  # 力こぶ
            hand(ex - s * 4, 58, arm * 0.62)
    else:           # 両腕を上げるヒーローポーズ + トロフィー
        for s in (-1, 1):
            p.line([(cx + s * (rx - 6), sh), (cx + s * (rx + 14), 38)], GREEN, arm)
            hand(cx + s * (rx + 14), 34)
        tx = cx + rx + 14
        p.ell(tx - 11, 10, 5, 6, None, outline=GOLD, width=2)   # 取っ手
        p.ell(tx + 11, 10, 5, 6, None, outline=GOLD, width=2)
        p.rect(tx - 11, 2, tx + 11, 24, GOLD, r=6)
        p.rect(tx - 3, 23, tx + 3, 30, GOLD_D)
        p.rect(tx - 9, 29, tx + 9, 33, GOLD_D, r=1)

    # --- 頭
    for s in (-1, 1):  # 耳の房
        p.poly([(cx + s * (hx - 8), 42), (cx + s * (hx + 2), 26), (cx + s * (hx - 24), 38)], GREEN)
    p.ell(cx, 60, hx, 25, GREEN)
    if st >= 2:  # ヘッドバンド
        band = GOLD if st == 6 else WHITE
        p.rect(cx - hx + 5, 40, cx + hx - 5, 46, band, r=3)
        p.rect(cx - hx + 5, 45, cx + hx - 5, 47, SHIRT_G if st < 6 else GOLD_D)
    for s in (-1, 1):  # ヘッドホン
        p.ell(cx + s * (hx - 1), 52, 6, 8, BLACK)
    if st == 6:  # 王冠
        p.poly([(cx - 14, 36), (cx - 14, 22), (cx - 7, 29), (cx, 18), (cx + 7, 29), (cx + 14, 22), (cx + 14, 36)], GOLD)

    # --- 表情
    ey = 60
    if expr == "sleepy":
        for s in (-1, 1):
            p.arc(cx + s * 12, ey - 2, 8, 6, 20, 160, INK, 2.2)
        p.text((cx + hx + 6, 32), "z", 11, (200, 220, 255))
        p.text((cx + hx + 14, 22), "z", 8, (200, 220, 255))
    elif expr == "joy":
        for s in (-1, 1):
            p.arc(cx + s * 12, ey + 3, 8, 7, 200, 340, INK, 2.4)
            p.ell(cx + s * 20, ey + 10, 5, 3, (255, 140, 150, 170))
    else:
        for s in (-1, 1):
            p.ell(cx + s * 12, ey, 9, 9, WHITE)
            p.ell(cx + s * 12, ey + 1, 4.5, 4.5, INK)
            p.ell(cx + s * 12 + 1.5, ey - 1.5, 1.4, 1.4, WHITE)
        if expr == "excited":
            for s in (-1, 1):
                p.line([(cx + s * 20, ey - 14), (cx + s * 6, ey - 10)], INK, 2.4)
    p.poly([(cx - 6, 68), (cx + 6, 68), (cx, 78)], ORANGE)  # くちばし
    if expr == "joy":
        p.poly([(cx - 5, 73), (cx + 5, 73), (cx, 79)], (220, 90, 40))

    # --- 前面エフェクト
    if expr == "calm" or st == 1:
        p.ell(cx + hx - 2, 40, 3.2, 4.5, (127, 208, 255))
        p.poly([(cx + hx - 5, 39), (cx + hx + 1, 39), (cx + hx - 2, 32)], (127, 208, 255))
    if st == 2 or expr == "excited":
        for x, y, r in ((22, 60, 5), (140, 44, 4), (130, 120, 4)):
            p.star(x, y, r, (255, 246, 176))
    if st == 4:
        for x, y, r in ((20, 50, 8), (142, 36, 7), (14, 120, 5), (146, 116, 6)):
            p.star(x, y, r, (255, 230, 90))
        for y in (70, 82):
            p.line([(4, y), (18, y)], (230, 240, 255, 180), 1.6)
            p.line([(142, y + 6), (156, y + 6)], (230, 240, 255, 180), 1.6)
    if st == 6 or expr == "joy":
        cols = [(255, 107, 107), (77, 210, 255), (255, 213, 74), (160, 107, 255)]
        for k in range(16):
            x, y = 8 + (k * 37) % 146, 6 + (k * 53) % 70
            if 44 < x < 116 and y > 24:  # 顔にかからないようにする
                continue
            p.rect(x, y, x + 3.5, y + 6, cols[k % 4], r=0.8)
    return p.out(160, 180)


# ---------------------------------------------------------------- 背景

def draw_background(st):
    p = Pen(320, 180)
    def grad(top, bottom, y0=0, y1=180):
        for y in range(y0, y1):
            t = (y - y0) / max(1, y1 - y0)
            p.rect(0, y, 320, y + 1, tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)))

    if st == 1:    # 朝の自宅
        grad((255, 232, 205), (250, 214, 180), 0, 140)
        p.rect(0, 140, 320, 180, (196, 150, 110))
        p.rect(28, 26, 110, 100, (200, 230, 255), r=4, outline=WHITE, width=4)
        p.line([(69, 26), (69, 100)], WHITE, 3)
        p.ell(250, 52, 14, 14, (255, 220, 120))
    elif st == 2:  # 朝の公園
        grad((170, 215, 255), (225, 240, 255), 0, 130)
        p.rect(0, 130, 320, 180, (130, 200, 100))
        for x in (40, 285):
            p.rect(x - 5, 80, x + 5, 132, (130, 90, 60))
            p.ell(x, 72, 28, 26, (80, 160, 80))
    elif st == 3:  # 明るいジム
        p.rect(0, 0, 320, 130, (235, 235, 230))
        for x in (30, 130, 230):
            p.rect(x, 18, x + 60, 88, (190, 225, 255), r=3, outline=(210, 210, 205), width=3)
        p.rect(0, 130, 320, 180, (205, 160, 110))
        for x in range(0, 320, 40):
            p.line([(x, 130), (x - 20, 180)], (185, 140, 95), 1)
    elif st == 4:  # ビーチ
        grad((110, 180, 245), (200, 230, 255), 0, 100)
        p.rect(0, 100, 320, 128, (60, 150, 200))
        p.rect(0, 128, 320, 180, (240, 215, 165))
        p.ell(280, 34, 16, 16, (255, 240, 170))
        p.line([(30, 128), (38, 60)], (140, 100, 60), 5)
        for a in (-60, -20, 20, 60):
            r = math.radians(a - 90)
            p.line([(38, 60), (38 + math.cos(r) * 28, 60 + math.sin(r) * 16 + 10)], (70, 150, 70), 4)
    elif st == 5:  # 炎のジム
        grad((40, 20, 20), (90, 35, 20), 0, 130)
        p.rect(0, 130, 320, 180, (120, 80, 50))
        for i in range(12):
            x = 12 + i * 27
            h = 50 + (i * 23) % 40
            p.poly([(x - 16, 132), (x, 132 - h), (x + 16, 132)], (255, 110, 30, 220))
            p.poly([(x - 8, 132), (x, 132 - h * 0.6), (x + 8, 132)], (255, 210, 80, 230))
    else:          # 朝日の山頂
        grad((255, 170, 90), (255, 230, 170), 0, 130)
        for i in range(10):
            a = math.pi * (0.05 + 0.9 * i / 9)
            p.line([(160, 118), (160 - math.cos(a) * 260, 118 - math.sin(a) * 200)], (255, 245, 200, 120), 5)
        p.ell(160, 118, 30, 30, (255, 240, 150))
        p.poly([(0, 180), (0, 120), (70, 70), (160, 140), (250, 60), (320, 115), (320, 180)], (90, 80, 120))
        p.poly([(0, 180), (0, 150), (100, 120), (200, 160), (320, 130), (320, 180)], (60, 55, 90))
    return p.out(320, 180).convert("RGB")


# 今日の達成率に合わせた背景の明るさ（眠い=暗い、大喜び=明るい）
BRIGHT = {"sleepy": 0.6, "calm": 0.85, "excited": 1.0, "joy": 1.12}


def screen(st, expr, pct, next_pct, streak):
    bg = draw_background(st)
    bg = Image.eval(bg, lambda v: min(255, int(v * BRIGHT[expr])))
    img = Image.new("RGB", (320, 240), (20, 24, 32))
    img.paste(bg, (0, 0))
    spr = draw_character(st, expr)
    img.paste(spr, (80, 0), spr)
    p = Pen(320, 240)
    p.rect(0, 180, 320, 240, (20, 24, 32, 255))
    p.text((10, 194), f"Lv.{st} {NAMES[st - 1]}", 13, WHITE, anchor="lm")
    p.text((310, 194), f"連続 {streak}日", 11, (200, 205, 215), anchor="rm")
    p.text((10, 213), f"今日 {pct}%", 10, WHITE, anchor="lm")
    p.rect(10, 222, 150, 229, (60, 64, 72), r=3)
    p.rect(10, 222, 10 + 140 * pct / 100, 229, (126, 217, 87), r=3)
    p.text((170, 213), "次の進化まで" + ("  最大" if st == 6 else f" {next_pct}%"), 10, WHITE, anchor="lm")
    p.rect(170, 222, 310, 229, (60, 64, 72), r=3)
    p.rect(170, 222, 170 + 140 * (100 if st == 6 else next_pct) / 100, 229, GOLD, r=3)
    ui = p.out(320, 240)
    img.paste(ui, (0, 0), ui)
    return img


def main():
    for sub in ("sprites", "bg", "preview"):
        (OUT / sub).mkdir(parents=True, exist_ok=True)

    sprites = {}
    for st in range(1, 7):
        draw_background(st).save(OUT / "bg" / f"stage{st}.png", optimize=True)
        for ex in EXPRS:
            im = draw_character(st, ex)
            im.save(OUT / "sprites" / f"stage{st}_{ex}.png", optimize=True)
            sprites[(st, ex)] = im

    # 実機画面イメージ: ステージごとに達成率を変えて 4 種の表情を見せる
    demo = {1: ("sleepy", 15, 40, 3), 2: ("calm", 45, 70, 8), 3: ("excited", 70, 30, 15),
            4: ("excited", 85, 60, 30), 5: ("joy", 100, 85, 60), 6: ("joy", 100, 100, 120)}
    screens = []
    for st, (ex, pct, nxt, streak) in demo.items():
        im = screen(st, ex, pct, nxt, streak)
        im.save(OUT / "preview" / f"stage{st}.png", optimize=True)
        screens.append(im)

    # 一覧（スプライト 6 行 × 表情 4 列、チェック柄の上）
    pad = 6
    sheet = Image.new("RGB", (4 * (160 + pad) + pad, 6 * (180 + pad) + pad), (236, 236, 236))
    for (st, ex), im in sprites.items():
        x, y = pad + EXPRS.index(ex) * (160 + pad), pad + (st - 1) * (180 + pad)
        sheet.paste(im, (x, y), im)
    sheet.save(OUT / "contact_sprites.png", optimize=True)

    sheet2 = Image.new("RGB", (3 * (320 + pad) + pad, 2 * (240 + pad) + pad), (236, 236, 236))
    for i, im in enumerate(screens):
        sheet2.paste(im, (pad + (i % 3) * (320 + pad), pad + (i // 3) * (240 + pad)))
    sheet2.save(OUT / "contact_screens.png", optimize=True)
    print(f"出力: {OUT}")


if __name__ == "__main__":
    main()
