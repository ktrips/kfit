#!/usr/bin/env python3
"""AppleWatch Diet 100メソッド — Markdown 原稿生成スクリプト
   gen_aw_diet_pb.py の METHODS データを読み込み、画像付き .md を生成する。
"""

import sys
import os
import glob
import importlib.util

# ── gen_aw_diet_pb.py の METHODS / FITINGO_FEATURES / DAILY_ROUTINE をロード ──
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PB_SCRIPT   = os.path.join(SCRIPT_DIR, 'gen_aw_diet_pb.py')

spec   = importlib.util.spec_from_file_location('pb', PB_SCRIPT)
pb_mod = importlib.util.module_from_spec(spec)
# モジュール実行は不要なので、METHODS 部分だけ抽出
# gen_aw_diet_pb.py は top-level に METHODS リストを定義しているため
# exec() で安全にロードする
with open(PB_SCRIPT, encoding='utf-8') as f:
    src = f.read()

# METHODS の定義部分だけを実行できるよう、main() 以降を除去して exec
# 方法: 'if __name__ == ' 以降をカット
cut_idx = src.find("\nif __name__")
safe_src = src[:cut_idx] if cut_idx != -1 else src
# ---- main() 呼び出しも除去
safe_src = safe_src.replace('\nmain()', '')

namespace = {}
try:
    exec(compile(safe_src, PB_SCRIPT, 'exec'), namespace)
except Exception as e:
    # python-docx がインストールされていない場合でも METHODS は取得できる
    # docx 系のエラーは無視して namespace から必要データだけ拾う
    pass

METHODS          = namespace.get('METHODS', [])
FITINGO_FEATURES = namespace.get('FITINGO_FEATURES', [])

# ── 画像ディレクトリ ─────────────────────────────────────────────────
SHOT_BASE = os.path.join(SCRIPT_DIR, 'screenshots')

def imgs_in(folder):
    """フォルダ内の画像をソートして返す（相対パス）"""
    exts = ['*.jpg', '*.JPG', '*.png', '*.PNG', '*.jpeg']
    paths = []
    for ext in exts:
        paths.extend(glob.glob(os.path.join(SHOT_BASE, folder, ext)))
    # 重複除去（大文字・小文字違い）
    seen = set()
    result = []
    for p in sorted(paths):
        key = os.path.basename(p).lower()
        if key not in seen:
            seen.add(key)
            result.append(os.path.relpath(p, SCRIPT_DIR))
    return result

watch_imgs = imgs_in('watch')
fit_imgs   = imgs_in('fit')
food_imgs  = imgs_in('food')
mind_imgs  = imgs_in('mind')
main_imgs  = imgs_in('main')

# AppleWatch_Diet_PB.docx から抽出したリアル写真（from_pb/）
PB_DIR = os.path.join(SCRIPT_DIR, 'screenshots', 'from_pb')

def pb(fname):
    p = os.path.join('screenshots', 'from_pb', fname)
    return p if os.path.exists(os.path.join(SCRIPT_DIR, p)) else None

# 画像内容 → カテゴリ適合度
# image1.png  = Apple Watch 文字盤（青バンド）
# image2.png  = Apple Watch 文字盤（夕焼け写真背景）
# image3.png  = グラフ「1日の消費カロリー」
# image4.jpeg = マインドフルネス/呼吸サマリー
# image5.jpeg = ワークアウト記録（カロリー・心拍）
_img1 = pb('image1.png')
_img2 = pb('image2.png')
_img3 = pb('image3.png')
_img4 = pb('image4.jpeg')
_img5 = pb('image5.jpeg')

def _build_pool(*primaries, fallback=None):
    return [p for p in primaries if p] + (fallback or [])

# ── カテゴリ別 画像プール ─────────────────────────────────────────────
CAT_IMGS = {
    "I. エネルギー消費を増やす":  _build_pool(_img5, _img1, _img2, fallback=watch_imgs + fit_imgs),
    "II. 食事管理":               _build_pool(_img3, _img1, fallback=food_imgs + main_imgs),
    "III. マインドフルネスと睡眠": _build_pool(_img4, _img1, fallback=mind_imgs),
    "IV. Fitingoアプリとの連携":  _build_pool(_img1, _img5, _img2, fallback=main_imgs + fit_imgs),
}

# カテゴリごとのカウンタ（ラウンドロビン）
cat_counters = {k: 0 for k in CAT_IMGS}

def get_img_for(method):
    """メソッドのカテゴリに合った画像パスを返す（なければ None）"""
    cat   = method.get('cat', '')
    pool  = CAT_IMGS.get(cat, [])
    if not pool:
        return None
    idx = cat_counters[cat] % len(pool)
    cat_counters[cat] += 1
    return pool[idx]

# ── Markdown 生成 ─────────────────────────────────────────────────────
lines = []

lines.append("# AppleWatch Diet Ultra2 — 100のダイエット方法")
lines.append("")
lines.append("> **著者**: 吉田 顕一  ")
lines.append("> Apple Watchで簡単、手軽にダイエット、健康的な生活を送る方法")
lines.append("")
lines.append("---")
lines.append("")

# ── はじめに ───────────────────────────────────────────────────────────
lines.append("## はじめに")
lines.append("")
lines.append(
    "Apple Watch Ultra 2を手首に着けるだけで、あなたのダイエットは"
    "「管理するもの」から「楽しむもの」に変わります。"
)
lines.append("")
lines.append(
    "本書では、Apple WatchとFitingo（フィティンゴ）アプリを最大限に活用した"
    "100のメソッドを、カテゴリ別に紹介します。"
)
lines.append("")
lines.append("---")
lines.append("")

# ── 目次 ──────────────────────────────────────────────────────────────
lines.append("## 目次")
lines.append("")
prev_cat = None
for m in METHODS:
    if m['cat'] != prev_cat:
        lines.append(f"")
        lines.append(f"### {m['cat']}")
        prev_cat = m['cat']
    lines.append(f"- [No.{m['no']:03d} {m['title']}](#{m['no']:03d})")
lines.append("")
lines.append("---")
lines.append("")

# ── Fitingo 20機能 ──────────────────────────────────────────────────────
if FITINGO_FEATURES:
    lines.append("## Fitingo アプリ 20の機能")
    lines.append("")
    lines.append(
        "Apple WatchとiPhoneを最大限に活かすFitingoの主要機能を紹介します。"
        "これらの機能を組み合わせることで、ダイエットを「楽しく続けられる習慣」に変えられます。"
    )
    lines.append("")
    for feat in FITINGO_FEATURES:
        lines.append(f"### {feat['no']:02d}. {feat['icon']} {feat['name']}")
        lines.append(f"*{feat['short']}*")
        lines.append("")
        lines.append(feat['desc'])
        lines.append("")
    lines.append("---")
    lines.append("")

# ── 100メソッド ────────────────────────────────────────────────────────
lines.append("## 100のダイエット方法")
lines.append("")

prev_cat = None
for m in METHODS:
    # カテゴリ見出し
    if m['cat'] != prev_cat:
        lines.append(f"---")
        lines.append(f"")
        lines.append(f"## {m['cat']}")
        lines.append("")
        prev_cat = m['cat']

    # アンカー用 id
    no_str = f"{m['no']:03d}"
    lines.append(f'<a id="{no_str}"></a>')
    lines.append("")
    lines.append(f"### No.{no_str} {m['icon']} {m['title']}")
    lines.append("")

    # 画像挿入
    img_path = get_img_for(m)
    if img_path:
        alt = f"No.{no_str} - {m['title']}"
        lines.append(f"![{alt}]({img_path})")
        lines.append("")

    # 本文
    lines.append(m['body'])
    lines.append("")

    # やり方
    lines.append("#### 📋 やり方")
    lines.append("")
    for step in m['how']:
        lines.append(f"- {step}")
    lines.append("")

    # ポイント
    lines.append("#### 💡 ポイント")
    lines.append("")
    lines.append(f"> {m['point']}")
    lines.append("")

lines.append("---")
lines.append("")

# ── おわりに ─────────────────────────────────────────────────────────
lines.append("## おわりに")
lines.append("")
lines.append("100の方法を最後まで読んでいただき、ありがとうございます。")
lines.append("")
lines.append(
    "ダイエットに「魔法」はありません。しかし、Apple WatchとFitingoがあれば、"
    "地道な努力を「楽しい習慣」に変える魔法はあります。"
)
lines.append("")
lines.append(
    "Apple Watchをはめて、Fitingoを開いて、さあ今日も始めましょう。"
)
lines.append("")
lines.append("*　　　　　　　　　　　　　　　　　吉田 顕一*")
lines.append("")
lines.append("---")
lines.append("")

# ── 著者プロフィール ───────────────────────────────────────────────────
lines.append("## 著者プロフィール")
lines.append("")
lines.append("**吉田 顕一（よしだ けんいち）**")
lines.append("")
lines.append(
    "Apple Watchユーザー歴10年以上。Fitingo（kfit）アプリ開発者。"
    "Apple Watch・iOSアプリを活用した習慣形成と健康管理の専門家として、"
    "数千人のユーザーのダイエット・健康改善をサポート。"
    "「テクノロジーを使って、無理なく楽しく健康になる」をモットーに、"
    "Apple WatchとFitingoの機能を最大限に活かしたメソッドを研究・実践中。"
)
lines.append("")

# ── 書き出し ─────────────────────────────────────────────────────────
output_path = os.path.join(SCRIPT_DIR, 'AppleWatchDiet_100methods.md')
with open(output_path, 'w', encoding='utf-8') as f:
    f.write('\n'.join(lines) + '\n')

print(f"✅ Markdown 生成完了: {output_path}")
print(f"   メソッド数: {len(METHODS)}")
if FITINGO_FEATURES:
    print(f"   Fitingo機能数: {len(FITINGO_FEATURES)}")
print(f"   総行数: {len(lines)}")
