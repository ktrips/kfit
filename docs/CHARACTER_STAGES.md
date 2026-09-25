# FitinGO キャラクター 6 ステージ 制作仕様（案）

M5Stack の FitinGO 画面（[M5STACK_ACCESSORY_DESIGN.md](M5STACK_ACCESSORY_DESIGN.md) の 3.4）に表示する、Fitingo キャラクターの成長 6 ステージの制作仕様です。既存の動画（`fitingo_mv_*.mp4`）と `mascot.png` の画風を基準に、**体つき・服装・道具・背景・ポーズ・エフェクトを組み合わせて**ステージを表現します。

> 写実 CG 風の画像は画像生成 AI での制作が必要です（`tools/character_stages/generate.py`、API キーが必要）。すぐ M5 に載せられる**シンプルなフラット版**は `tools/character_stages/simple/` に生成済みです（7 章）。

---

## 1. 基準にする画風（既存素材から読み取った特徴）

| 要素 | 特徴 |
|---|---|
| 画風 | 写実的な 3D CG 風のマスコット。毛並みのある質感、映画のような光 |
| キャラ | 緑色のフクロウ。大きな白い目、オレンジのくちばし、頭に白と緑のヘッドバンド、両側にヘッドホン |
| 服装 | 緑のタンクトップ（胸に白字で `FITINGO`）、緑のショーツ（白いライン）、緑と白のスニーカー |
| 背景 | 南国のビーチ（青空・ヤシ）、炎が上がるジム（マット・ダンベル・大きな窓） |
| 演出 | キラキラ（黄色い星、水色の粒）、炎、砂ぼこり |
| 補足 | `mascot.png` はフラットなイラスト調（炎の背景で力こぶ）。写実 CG 風の方と混在しているため、**どちらを正とするか先に決める**（本仕様は写実 CG 風を基準にする） |

---

## 2. ステージごとの組み合わせ表

同じキャラ（顔・色・プロポーションのベース）のまま、下の 6 要素を変えて成長を見せます。

| | 1 ひよこ | 2 ビギナー | 3 アスリート | 4 マッスル | 5 ムキムキ | 6 レジェンド |
|---|---|---|---|---|---|---|
| **体つき** | 小さく丸い、腕と脚が細い | 少し引き締まる | 逆三角形、腕・脚に筋 | 胸板と腕が大きい | 全身が非常に大きく、筋の凹凸 | ムキムキ + 堂々とした体格（ピーク） |
| **服装** | ロゴなしの白い大きめ T シャツ、ヘッドバンドなし | 緑の T シャツ（小さく `FITINGO`）、白いヘッドバンド | 緑のタンクトップ + ショーツ、ヘッドバンド + ヘッドホン | 既存と同じタンクトップ、ヘッドバンド + ヘッドホン | タンクトップ + リストラップ + トレーニングベルト | 金の縁取りのタンクトップ、金のヘッドバンド、王冠 |
| **道具** | タオルを首に、水のボトル | ヨガマット、軽いダンベル | ダンベル | バーベル | 重いバーベル／ケトルベル | 金のトロフィーまたは金のバーベル |
| **背景** | 朝の自宅・公園（淡い光） | 朝の公園、小さなジム | 明るいジム（自然光） | ビーチ（晴れ）／夕方のジム | 炎のジム（既存の背景） | 朝日の山頂／アリーナ（光の筋） |
| **ポーズ** | 手を振る、ぎこちなくストレッチ | 軽いスクワット、その場走り | スクワット、腕立て | ダブルバイセップス（力こぶ） | ジャンプして力こぶ、吠える | 両腕を高く上げるヒーローポーズ |
| **エフェクト** | 汗のしずく | 小さなキラキラ | 緑のオーラ | 黄色いキラキラ + 風 | 炎 + 橙のオーラ | 金のオーラ + 光の筋 + 紙吹雪 |

体つき・服装・道具・背景は**ステージで固定**し、次の「今日の頑張り」で変わるものは別レイヤーにします。

## 3. 今日の達成率で変わる要素（ステージと独立）

| 今日の達成率 | 表情 | 背景の明るさ | 追加のエフェクト |
|---|---|---|---|
| 0〜29% | 眠そう（目を細める） | 暗め（朝焼け前） | なし |
| 30〜59% | ふつう + 汗 | やや青い | 汗のしずく |
| 60〜99% | 目に力、眉が上がる | 明るい | 小さなキラキラ |
| 100% | 笑顔で目を閉じる（^ ^） | 金色寄り | 大きなキラキラ + 紙吹雪 + 星 |

これで「ステージ 6 通り × 表情 4 通り」の 24 通りが、ステージの体つきに表情を焼き込んだスプライトで表せます。

---

## 4. M5 での組み立て（レイヤー構成）

すべてを 1 枚絵として持たず、**重ねて表示**することで素材数を抑えます。

| レイヤー | 内容 | 枚数 | 形式 |
|---|---|---|---|
| L0 背景 | ステージ別の 6 場面（明るさは色補正で 4 段階に） | 6 | 320×180 JPEG |
| L1 背面エフェクト | オーラ・炎・光の筋（ステージ 3〜6） | 4 | 透過 PNG |
| L2 キャラ | ステージ × 表情 4 種（服装・道具・ポーズを含む） | 24 | 透過 PNG（約 160×180） |
| L3 前面エフェクト | キラキラ、紙吹雪、汗、レップごとのスパーク | 5〜6 | 透過 PNG（アニメ用に数フレーム） |

**容量の見積もり（実測ではなく目安）**: キャラ 24 枚 + 背景 6 枚 + エフェクト 数十枚で **2MB 前後**。CoreS3 のフラッシュ（16MB）に十分収まり、ファームウェアと別の素材パックとして更新できます。

**レップ連動の反応**: L2 のスプライトを一瞬拡大（脈動）し、L3 のスパークを重ねる。ステージごとの追加の絵は不要です。

**進化の演出**: 白いフラッシュ → 旧ステージのシルエットが膨らむ → 新ステージに切り替え、L3 に金のキラキラ。画像は既存のレイヤーの流用で足ります。

**画面レイアウト（320×240）**: 上 180px にキャラ、下 60px に「Lv・名前」「今日の達成率」「次の進化まで」のバーと文字。

---

## 5. 画像生成の進め方

1. **基準シートを作る**: 既存の動画から、正面・全身・素の状態のフレームを選び、キャラクターの基準（顔・色・プロポーション・ヘッドホン）として固定
2. **ステージごとに生成**: 参照画像を入力できる画像生成 AI（OpenAI・Google など）に、基準画像 + ステージの指示（下記）を渡し、**同じキャラの別バージョン**として生成
3. **表情の差し替え**: 各ステージの画像を基準に、表情だけ変えた版を作る（体つき・服装は変えない）
4. **切り抜き**: 単色背景（例: マゼンタ）で生成し、透過 PNG に切り抜く。背景は別に生成
5. **M5 用に調整**: 160×180 程度に縮小、色数と圧縮を調整し、**実機の画面で見た目を確認**（小さな画面では細部が潰れるため、輪郭と色の差を強めにする）
6. **一貫性の確認**: 6 ステージを並べて、同じキャラに見えるか、成長が段階的に伝わるかを確認

### 共通の指示（スタイル固定用）

```
Photorealistic 3D CG mascot, a green owl with large white eyes, orange beak,
white-and-green headband and black headphones on both sides of the head,
soft feathery texture, cinematic lighting, full body, character stays the same
across images (same face and proportions). Shot on a flat magenta background
for cutout. No text except "FITINGO" printed on the shirt.
```

### ステージ別の指示（共通の指示に追加）

| ステージ | 追加の指示（英語） |
|---|---|
| 1 | `small round body, thin arms and legs, oversized plain white T-shirt with no logo, no headband, towel around neck, holding a water bottle, shy waving pose, one sweat drop` |
| 2 | `slightly toned body, small arms, green T-shirt with small FITINGO print, white headband, holding a light dumbbell, standing on a yoga mat, light squat pose, a few small sparkles` |
| 3 | `athletic V-shaped body, defined arms and legs, green tank top with FITINGO and shorts, headband and headphones, holding a dumbbell, squat pose, faint green aura` |
| 4 | `muscular body with big chest and arms, green FITINGO tank top and shorts, headband and headphones, front double biceps pose, yellow sparkles and light wind` |
| 5 | `very muscular body with visible muscle definition, tank top with wrist wraps and weightlifting belt, holding a heavy barbell, jumping flex pose, roaring, orange flames and aura` |
| 6 | `peak muscular physique, gold-trimmed FITINGO tank top, golden headband with a small crown, holding a golden trophy, heroic pose with both arms raised, golden aura, light rays, confetti` |

| 表情（各ステージに追加） | 指示 |
|---|---|
| 眠そう | `sleepy half-closed eyes, relaxed` |
| ふつう | `calm eyes, slight smile, small sweat drop` |
| やる気 | `determined eyes, raised eyebrows` |
| 大喜び | `eyes closed in a big happy smile, joyful` |

背景は別の指示で生成します（例: `bright gym with natural light, wooden floor, no characters`、`tropical beach with blue sky and palm trees, no characters` など、ステージ表の背景に合わせる）。

---

## 6. 注意点

- **一貫性**: 画像生成 AI は、画像ごとに顔や体型が変わりやすい。参照画像の固定と、生成後の並べての確認が必須です
- **文字**: 胸の `FITINGO` の文字は崩れやすい。崩れる場合は生成後に文字だけ合成します
- **小さな画面**: 320×240 では細部が見えにくい。ステージの違いは、体のシルエット・服装の色・エフェクトの大きさで出す
- **権利**: 既存キャラは、よく知られた語学アプリのフクロウのマスコットに雰囲気が似ています。ステージ画像を増やして公開する前に、権利面（商標・著作権・審査）の確認を推奨します
- **生成 AI の利用条件**: 商用利用・生成物の権利の扱いは、利用するサービスの規約を確認してください
- **画風の統一**: 写実 CG 風（動画）とイラスト調（`mascot.png`）が混在している。**アイコンなど他の画面との統一**も含め、どちらに寄せるかを最初に決める

---

## 7. シンプル版（M5 画面用・生成済み）

画像生成 AI を使わず、図形だけで描いたフラットな版です。2 章の組み合わせ（体つき・服装・道具・背景・ポーズ・エフェクト）と 3 章の表情 4 種をそのまま反映しています。まず実機で動かすための素材で、写実 CG 版ができたら差し替えます。

| ファイル | 内容 |
|---|---|
| `tools/character_stages/simple/sprites/stage{1-6}_{sleepy,calm,excited,joy}.png` | 160×180 透過 PNG、24 枚 |
| `tools/character_stages/simple/bg/stage{1-6}.png` | 320×180 背景、6 枚（自宅・公園・ジム・ビーチ・炎のジム・山頂） |
| `tools/character_stages/simple/preview/stage{1-6}.png` | 320×240 の実機画面イメージ（下部に Lv・達成率・次の進化までのバー） |
| `contact_sprites.png` / `contact_screens.png` | 確認用の一覧 |

合計約 0.7MB（一覧を除く）。再生成は `python3 tools/character_stages/simple_sprites.py`（Pillow が必要）。M5 では背景を描いてからキャラの PNG を重ね、表情は達成率、背景の明るさは表情に合わせて変えます（プレビューと同じ組み立て）。

## 8. 写実 CG 版の生成手順

```bash
export OPENAI_API_KEY=...                                          # リポジトリに置かない
python3 tools/character_stages/generate.py --stages 1 --dry-run    # プロンプト確認（無料）
python3 tools/character_stages/generate.py --stages 1              # ステージ1の4枚を試作
tools/character_stages/pack.sh                                     # 切り抜き・M5 用縮小・一覧
```

基準画像は `tools/character_stages/reference.png`（`fitingo_mv_squat.mp4` の 3.2 秒）。生成物（`out/`・`m5/`）は Git 管理外です。

