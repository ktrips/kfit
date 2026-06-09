#!/usr/bin/env python3
"""
KDP ペーパーバック フルラップ表紙 PDF 作成スクリプト
KDP仕様: https://kdp.amazon.co.jp/ja_JP/help/topic/G201953020

構成 (左→右):
  [左裁ち落とし 3.2mm] [裏表紙 210mm] [背表紙] [表表紙 210mm] [右裁ち落とし 3.2mm]
  高さ: [上裁ち落とし 3.2mm] + [257mm] + [下裁ち落とし 3.2mm]

用紙: プレミアムカラー（白）
背幅計算: ページ数 × 0.0596mm
"""

import sys, os
from PIL import Image, ImageDraw, ImageColor

# ── 設定 ─────────────────────────────────────────────────────────────────
PAGE_COUNT   = 84          # KDPプレビューで確認したページ数（更新が必要なら変更）
DPI          = 300
MM_PER_INCH  = 25.4
DPI_PER_MM   = DPI / MM_PER_INCH  # = 11.811 px/mm

TRIM_W_MM    = 210.0       # 判型 幅
TRIM_H_MM    = 257.0       # 判型 高さ
BLEED_MM     = 3.2         # 裁ち落とし（上下・外側）

# 背幅: プレミアムカラー（白）= ページ数 × 0.0596mm
SPINE_MM     = PAGE_COUNT * 0.0596
print(f"背幅: {SPINE_MM:.2f}mm ({PAGE_COUNT} ページ × 0.0596)")

# ── ピクセル計算 ─────────────────────────────────────────────────────────
def mm2px(mm): return round(mm * DPI_PER_MM)

# KDP仕様に合わせて端数を round() で丸め、各辺を足し合わせる
BLEED_PX     = mm2px(BLEED_MM)           # 38px
TRIM_W_PX    = mm2px(TRIM_W_MM)          # 2480px
TRIM_H_PX    = mm2px(TRIM_H_MM)          # 3035px
SPINE_PX     = max(mm2px(SPINE_MM), 4)   # 最低4px（59px程度）

# KDP formula: 左裁ち + 裏表紙 + 背幅 + 表表紙 + 右裁ち
CANVAS_W     = BLEED_PX + TRIM_W_PX + SPINE_PX + TRIM_W_PX + BLEED_PX
# KDP formula: 上裁ち + 高さ + 下裁ち
CANVAS_H     = BLEED_PX + TRIM_H_PX + BLEED_PX

print(f"フルラップサイズ: {CANVAS_W} × {CANVAS_H} px @ {DPI}dpi")
print(f"  = {CANVAS_W/DPI_PER_MM:.1f}mm × {CANVAS_H/DPI_PER_MM:.1f}mm")
print(f"各セクション: 裁ち落とし{BLEED_PX}px | 裏表紙{TRIM_W_PX}px | 背表紙{SPINE_PX}px | 表表紙{TRIM_W_PX}px | 裁ち落とし{BLEED_PX}px")

# ── カラー ────────────────────────────────────────────────────────────────
NAVY         = (13, 27, 42)      # #0D1B2A
GREEN        = (34, 197, 94)     # #22c55e
DARK_GREEN   = (22, 101, 52)     # #166534

# ── ファイルパス ─────────────────────────────────────────────────────────
DOCS_DIR     = os.path.dirname(os.path.abspath(__file__))
ASSETS_DIR   = os.path.expanduser(
    "~/.cursor/projects/Users-kenichi-yoshida-Git-kfit/assets"
)
FRONT_PATH   = os.path.join(DOCS_DIR,   "paperback-cover-kdp.png")          # 縦長 2551×3106 ← 縦型表表紙
BACK_PATH    = os.path.join(ASSETS_DIR, "back-cover-portrait.png")          # 縦長 ← 縦型裏表紙
OUT_PNG      = os.path.join(DOCS_DIR, "paperback-cover-fullwrap.png")
OUT_PDF      = os.path.join(DOCS_DIR, "paperback-cover-fullwrap.pdf")

# ── ヘルパー ─────────────────────────────────────────────────────────────
def load_and_fill(path, target_w, target_h):
    """
    画像を読み込み、FILL（センタークロップ）でターゲットサイズに完全フィット。
    余白なし・アスペクト比を保ちつつターゲットを完全にカバーする。
    """
    img = Image.open(path).convert("RGB")
    src_w, src_h = img.size
    # 両方向をカバーするスケール（大きい方を採用 → はみ出した側をクロップ）
    scale = max(target_w / src_w, target_h / src_h)
    new_w = round(src_w * scale)
    new_h = round(src_h * scale)
    img = img.resize((new_w, new_h), Image.LANCZOS)
    # 中央クロップ
    left = (new_w - target_w) // 2
    top  = (new_h - target_h) // 2
    img  = img.crop((left, top, left + target_w, top + target_h))
    return img

# ── フルラップキャンバス作成 ─────────────────────────────────────────────
canvas = Image.new("RGB", (CANVAS_W, CANVAS_H), NAVY)
draw   = ImageDraw.Draw(canvas)

# 各セクションの X 開始位置
X_BACK_START  = 0
X_BACK_END    = BLEED_PX + TRIM_W_PX
X_SPINE_START = X_BACK_END
X_SPINE_END   = X_SPINE_START + SPINE_PX
X_FRONT_START = X_SPINE_END
X_FRONT_END   = CANVAS_W

SECTION_H     = CANVAS_H

# ── 裏表紙を配置（FILL: センタークロップで完全フィット） ──────────────────
print("裏表紙を配置中...")
back_w = X_BACK_END - X_BACK_START
if os.path.exists(BACK_PATH):
    back_img = load_and_fill(BACK_PATH, back_w, SECTION_H)
    canvas.paste(back_img, (X_BACK_START, 0))
else:
    print(f"  ⚠️  裏表紙が見つかりません: {BACK_PATH}")

# ── 背表紙（スパイン）を描画 ─────────────────────────────────────────────
print(f"背表紙を描画中... ({SPINE_PX}px = {SPINE_MM:.2f}mm)")
draw.rectangle([X_SPINE_START, 0, X_SPINE_END-1, SECTION_H-1], fill=NAVY)
draw.line([X_SPINE_START,   0, X_SPINE_START,   SECTION_H-1], fill=GREEN, width=2)
draw.line([X_SPINE_END - 1, 0, X_SPINE_END - 1, SECTION_H-1], fill=GREEN, width=2)

# ── 表表紙を配置（FILL: センタークロップで完全フィット） ──────────────────
print("表表紙を配置中...")
if os.path.exists(FRONT_PATH):
    front_w = X_FRONT_END - X_FRONT_START
    front_img = load_and_fill(FRONT_PATH, front_w, SECTION_H)
    canvas.paste(front_img, (X_FRONT_START, 0))
else:
    print(f"  ⚠️  表表紙が見つかりません: {FRONT_PATH}")

# ── セーフエリアのガイドライン（参考用：出力には影響なし） ────────────────
# セーフエリア: 裁ち落とし+3.2mmマージン内側
# KDP推奨: テキスト・重要要素はセーフエリア内に収める

# ── PNG 保存 ─────────────────────────────────────────────────────────────
print(f"PNG保存中: {OUT_PNG}")
canvas.save(OUT_PNG, "PNG", dpi=(DPI, DPI))
png_kb = os.path.getsize(OUT_PNG) // 1024
print(f"  サイズ: {png_kb} KB")

# ── PDF 保存 ─────────────────────────────────────────────────────────────
print(f"PDF保存中: {OUT_PDF}")
# PIL の PDF 出力は DPI メタデータを埋め込める
canvas_rgb = canvas.convert("RGB")
canvas_rgb.save(
    OUT_PDF,
    "PDF",
    resolution=DPI,      # PDFに300dpiを埋め込む
    save_all=False,
)
pdf_kb = os.path.getsize(OUT_PDF) // 1024
print(f"  サイズ: {pdf_kb} KB")

print(f"""
✅ フルラップ表紙を作成しました

【KDP提出サマリー】
  ファイル: {os.path.basename(OUT_PDF)}
  判型:     {TRIM_W_MM}mm × {TRIM_H_MM}mm (210×257mm)
  背幅:     {SPINE_MM:.2f}mm ({PAGE_COUNT}ページ × 0.0596mm)
  裁ち落とし: 3.2mm (各外縁)
  全体サイズ: {CANVAS_W/DPI_PER_MM:.1f}mm × {CANVAS_H/DPI_PER_MM:.1f}mm
  解像度:   {DPI} DPI
  ピクセル: {CANVAS_W} × {CANVAS_H} px

【KDPページ数が変わった場合】
  PAGE_COUNT の値を実際のページ数に変更して再実行してください。
  背幅 = ページ数 × 0.0596mm（プレミアムカラー・白）
""")
