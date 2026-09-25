#!/usr/bin/env python3
"""FitinGO キャラクター 6 ステージ × 表情 4 種を画像生成 AI で作る。

仕様: docs/CHARACTER_STAGES.md
基準画像 reference.png（既存動画 fitingo_mv_squat.mp4 の 3.2 秒のフレーム）を
参照として渡し、同じキャラのまま体つき・服装・道具・ポーズ・エフェクトを変える。

使い方:
  export OPENAI_API_KEY=...          # キーはリポジトリに置かない
  python3 tools/character_stages/generate.py --stages 1          # ステージ1の試作（表情4種）
  python3 tools/character_stages/generate.py --stages 1 --expr excited
  python3 tools/character_stages/generate.py                     # 全24枚

出力: tools/character_stages/out/stage{N}_{expr}.png（生成済みは再生成しない。--force で上書き）
生成 1 枚ごとに API 料金が発生する。
"""
import argparse
import base64
import json
import os
import sys
import urllib.error
import urllib.request
import uuid
from pathlib import Path

HERE = Path(__file__).resolve().parent
API_URL = "https://api.openai.com/v1/images/edits"

STYLE = (
    "Keep exactly the same character as the reference image: photorealistic 3D CG mascot, "
    "a green owl with large white eyes, orange beak, white-and-green headband and black "
    "headphones on both sides of the head, soft feathery texture, cinematic lighting. "
    "Same face, colors and proportions as the reference. Full body, centered, facing the viewer. "
    "Plain solid magenta (#FF00FF) background for cutout, no scenery, no shadow on background. "
    "No text anywhere except \"FITINGO\" printed on the shirt when a FITINGO shirt is described."
)

STAGES = {
    1: "small round body, thin arms and legs, oversized plain white T-shirt with no logo, "
       "no headband (headphones only), towel around neck, holding a water bottle, shy waving pose, one sweat drop",
    2: "slightly toned body, small arms, green T-shirt with small FITINGO print, white headband, "
       "holding a light dumbbell, standing on a yoga mat, light squat pose, a few small sparkles",
    3: "athletic V-shaped body, defined arms and legs, green tank top with FITINGO and shorts, "
       "headband and headphones, holding a dumbbell, squat pose, faint green aura",
    4: "muscular body with big chest and arms, green FITINGO tank top and shorts, headband and "
       "headphones, front double biceps pose, yellow sparkles and light wind",
    5: "very muscular body with visible muscle definition, green FITINGO tank top with wrist wraps "
       "and weightlifting belt, holding a heavy barbell, jumping flex pose, roaring, orange flames and aura",
    6: "peak muscular physique, gold-trimmed green FITINGO tank top, golden headband with a small crown, "
       "holding a golden trophy, heroic pose with both arms raised, golden aura, light rays, confetti",
}

EXPRESSIONS = {
    "sleepy": "sleepy half-closed eyes, relaxed",
    "calm": "calm eyes, slight smile, small sweat drop",
    "excited": "determined eyes, raised eyebrows",
    "joy": "eyes closed in a big happy smile, joyful",
}


def build_prompt(stage: int, expr: str) -> str:
    return f"{STYLE} Stage {stage}: {STAGES[stage]}. Expression: {EXPRESSIONS[expr]}."


def multipart(fields: dict, files: dict) -> tuple[bytes, str]:
    boundary = uuid.uuid4().hex
    parts = []
    for k, v in fields.items():
        parts.append(f"--{boundary}\r\nContent-Disposition: form-data; name=\"{k}\"\r\n\r\n{v}\r\n".encode())
    for k, path in files.items():
        parts.append(
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"{k}\"; filename=\"{path.name}\"\r\n"
            f"Content-Type: image/png\r\n\r\n".encode() + path.read_bytes() + b"\r\n"
        )
    parts.append(f"--{boundary}--\r\n".encode())
    return b"".join(parts), f"multipart/form-data; boundary={boundary}"


def generate(api_key: str, model: str, size: str, prompt: str, out: Path) -> None:
    body, ctype = multipart(
        {"model": model, "prompt": prompt, "size": size, "n": "1"},
        {"image": HERE / "reference.png"},
    )
    req = urllib.request.Request(API_URL, data=body, method="POST", headers={
        "Authorization": f"Bearer {api_key}", "Content-Type": ctype,
    })
    try:
        with urllib.request.urlopen(req, timeout=300) as res:
            data = json.load(res)
    except urllib.error.HTTPError as e:
        raise SystemExit(f"API エラー {e.code}: {e.read().decode(errors='replace')[:500]}")
    item = data["data"][0]
    if "b64_json" in item:
        out.write_bytes(base64.b64decode(item["b64_json"]))
    else:
        with urllib.request.urlopen(item["url"], timeout=120) as res:
            out.write_bytes(res.read())


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--stages", default="1,2,3,4,5,6")
    ap.add_argument("--expr", default=",".join(EXPRESSIONS))
    ap.add_argument("--model", default=os.environ.get("IMAGE_MODEL", "gpt-image-1"))
    ap.add_argument("--size", default="1024x1024")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--dry-run", action="store_true", help="プロンプトだけ表示（API を呼ばない）")
    args = ap.parse_args()

    stages = [int(s) for s in args.stages.split(",")]
    exprs = args.expr.split(",")
    out_dir = HERE / "out"
    out_dir.mkdir(exist_ok=True)

    api_key = os.environ.get("OPENAI_API_KEY", "")
    if not api_key and not args.dry_run:
        sys.exit("OPENAI_API_KEY が未設定です（--dry-run でプロンプトのみ確認できます）")

    for st in stages:
        for ex in exprs:
            out = out_dir / f"stage{st}_{ex}.png"
            prompt = build_prompt(st, ex)
            if args.dry_run:
                print(f"[{out.name}]\n{prompt}\n")
                continue
            if out.exists() and not args.force:
                print(f"skip {out.name}（生成済み）")
                continue
            print(f"生成中 {out.name} ...", flush=True)
            generate(api_key, args.model, args.size, prompt, out)
            print(f"  → {out}")


if __name__ == "__main__":
    main()
