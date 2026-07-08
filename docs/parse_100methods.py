#!/usr/bin/env python3
"""
AppleWatchDiet_100methods.md を解析して content_db.json を生成するスクリプト。
出力先: Packages/KFitCore/Sources/KFitCore/Resources/content_db.json
"""

import re
import json
import os

CATEGORY_MAP = {
    "I": "energy",        # エネルギー消費を増やす
    "II": "nutrition",    # 食事管理
    "III": "mind",        # マインドフルネスと睡眠
    "IV": "fitingo",      # Fitingoアプリとの連携
}

CATEGORY_LABELS = {
    "energy": "エネルギー消費",
    "nutrition": "食事管理",
    "mind": "マインド・睡眠",
    "fitingo": "Fitingo連携",
}

# 短い通知文言テンプレート（カテゴリ別）
NOTIFICATION_TEMPLATES = {
    "energy": ["今日も体を動かそう！", "1日1セット、積み重ねが力になる 💪", "立つだけで代謝が上がる！"],
    "nutrition": ["食事の記録、今日も1枚撮ろう 📸", "水分補給を忘れずに 💧", "食事前に深呼吸3回 🧘"],
    "mind": ["今日のHRVをチェック！", "ブリーズセッションでリセットしよう 🌬️", "良い睡眠が続けるチカラ 😴"],
    "fitingo": ["スパイラルを伸ばそう！", "今日の90秒、始めよう 🔥", "ストリークを守ろう 🔥"],
}

def parse_methods(md_path):
    with open(md_path, encoding="utf-8") as f:
        content = f.read()

    methods = []
    
    # メソッドブロックを切り出す
    # パターン: <a id="NNN"></a> から次の <a id= まで
    blocks = re.split(r'<a id="(\d+)"></a>', content)
    
    current_category = "energy"
    
    for i in range(1, len(blocks), 2):
        method_id = blocks[i].zfill(3)
        block = blocks[i + 1]
        
        # カテゴリ判定（IDから）
        num = int(method_id)
        if num <= 35:
            current_category = "energy"
        elif num <= 55:
            current_category = "nutrition"
        elif num <= 70:
            current_category = "mind"
        else:
            current_category = "fitingo"
        
        # タイトルと絵文字
        title_match = re.search(r'### No\.\d+ ([\S]+) (.+)', block)
        if not title_match:
            continue
        emoji = title_match.group(1)
        title = title_match.group(2).strip()
        
        # 本文（最初のセクション、#### より前）
        body_match = re.search(r'### No\.\d+.+?\n\n(?:!\[.*?\]\(.*?\)\n\n)?(.*?)(?=####|\Z)', block, re.DOTALL)
        description = ""
        if body_match:
            description = body_match.group(1).strip()
            # 画像マークダウンを除去
            description = re.sub(r'!\[.*?\]\(.*?\)', '', description).strip()
        
        # やり方ステップ
        steps = []
        steps_match = re.search(r'#### 📋 やり方\n\n(.*?)(?=####|\Z)', block, re.DOTALL)
        if steps_match:
            steps_text = steps_match.group(1).strip()
            steps = [s.lstrip('- ').strip() for s in steps_text.split('\n') if s.strip().startswith('-')]
        
        # ポイント
        tip = ""
        tip_match = re.search(r'#### 💡 ポイント\n\n> (.+?)(?=\n\n|\Z)', block, re.DOTALL)
        if tip_match:
            tip = tip_match.group(1).strip()
        
        # 短いコーチングメッセージ（通知用）
        if description:
            # 最初の文を取得（。または。\nで区切る）
            first_sentence = re.split(r'。', description)[0] + '。' if '。' in description else description[:50]
            coaching_message = first_sentence[:60]
        else:
            coaching_message = title
        
        # SNS 投稿テンプレート
        sns_post = f"【Fitingo メソッド #{method_id}】{title}\n\n{coaching_message}\n\n#Fitingo #AppleWatchダイエット #習慣化"
        
        # タグ
        tags = [current_category]
        if "Apple Watch" in title or "Watch" in title:
            tags.append("apple-watch")
        if any(w in title for w in ["スクワット", "腕立て", "腹筋", "ランニング", "ウォーキング", "筋力"]):
            tags.append("exercise")
        if any(w in title for w in ["食事", "カロリー", "水分", "栄養", "カフェイン"]):
            tags.append("nutrition")
        if any(w in title for w in ["睡眠", "マインドフル", "HRV", "瞑想", "ブリーズ"]):
            tags.append("mind")
        if any(w in title for w in ["Fitingo", "フィティンゴ"]):
            tags.append("fitingo-app")
        
        methods.append({
            "id": method_id,
            "emoji": emoji,
            "title": title,
            "category": current_category,
            "category_label": CATEGORY_LABELS[current_category],
            "description": description,
            "steps": steps,
            "tip": tip,
            "coaching_message": coaching_message,
            "sns_post": sns_post,
            "tags": list(set(tags)),
        })
    
    return methods


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(script_dir)
    
    md_path = os.path.join(script_dir, "AppleWatchDiet_100methods.md")
    output_path = os.path.join(repo_root, "Packages", "KFitCore", "Sources", "KFitCore", "Resources", "content_db.json")
    
    print(f"Parsing: {md_path}")
    methods = parse_methods(md_path)
    print(f"Parsed {len(methods)} methods")
    
    db = {
        "version": "1.0.0",
        "source": "AppleWatchDiet_100methods.md",
        "description": "Fitingo 100メソッド コンテンツDB。アプリ内コーチング・通知文言・SNS投稿の単一ソース。",
        "categories": {
            "energy":    {"label": "エネルギー消費を増やす", "emoji": "🔥", "range": "001-035"},
            "nutrition": {"label": "食事管理",               "emoji": "🍽️", "range": "036-055"},
            "mind":      {"label": "マインドフルネスと睡眠",  "emoji": "🧘", "range": "056-070"},
            "fitingo":   {"label": "Fitingoアプリとの連携",  "emoji": "📱", "range": "071-100"},
        },
        "methods": methods,
    }
    
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(db, f, ensure_ascii=False, indent=2)
    
    print(f"Output: {output_path}")
    print(f"Total methods: {len(methods)}")
    
    # 統計
    from collections import Counter
    cats = Counter(m["category"] for m in methods)
    for cat, cnt in sorted(cats.items()):
        print(f"  {cat}: {cnt}")


if __name__ == "__main__":
    main()
