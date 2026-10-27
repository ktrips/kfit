# Fitin on M5Stack CoreS3

Fitingo のマスコット **Fitin（フィッティン）** を、M5Stack CoreS3 上の Muse ガジェットとして動かすファームウェア差分です。

ベースは Meta の [muse-gadget-sdk](https://github.com/facebookincubator/muse-gadget-sdk)（Apache-2.0）。このフォルダは **Fitin 用の上書きファイルだけ** を持ちます。SDK 本体や SDK トークンは含めません。

## できること

- キャラ選択: **Muse** / **Fitin**（ヘッダーの名前をタップ、または SETTING）
- 画面は 3 枚: 右スワイプで **GO**、中央がホーム、左スワイプで SETTING
- GO: スクワット、歩数、心拍（Port B）、カメラ、Timers（瞑想/ストレッチ/ヨガ）、Health
- BMI270 でスクワット 20 回完了。歩数はポケットに入れても止まらず、スリープ中も計測が続く
- Health ポイント（スクワット・**10歩で1点**・タイマー・10回なでる）
- 1日 60 点以上で達成。ヘッダー `H94(D1)` は今日の点と連続日。タップで Health チェック
- キャラは連続達成するほど大きく逞しく、今日の点が少ないと薄い色・溜まると濃い色
- 日付・時刻・Wi-Fi・バッテリーはヘッダー右詰め
- Muse の返事や Health 診断は日本語で、ゴシック体（Noto Sans JP）で画面に出せる

CoreS3 に振動モーターはないため、うるさいスピーカーランブルは出さず、完了時などは短い可愛いチャープだけにしています。

## 操作方法

画面は横 320×240。中央がホーム（キャラ）、**右にスワイプ**で GO、**左にスワイプ**で SETTING。

### 話しかける

側面の **PWR** を押しているあいだ話す。離すと Muse / Fitin が答え、画面にキャプションが出ます。Muse アプリ（Developer mode）で `MuseGadget` としてペアし、SDK トークンがデバイスに入っている必要があります。

### ホームのヘッダー

右詰めの帯に、左から次の順です。

| 表示 | 操作 |
|---|---|
| **Muse**（ラベンダー） / **Fitin**（グリーン） | タップでキャラ切替 |
| **H94(D1)** | 今日の Health 点と連続達成日。タップで Health チェック |
| 日付・時刻 | 表示のみ |
| Wi-Fi・バッテリー | 表示のみ |

キャラはストリーク 0 日だと小さめ、7 日で最大。今日の Health 点が少ないと色が薄く、60 点付近で本色、それ以上はさらに濃くなります。

### ホームの四隅

キャラの四隅のアイコンで、GO と同じ動作をすぐ始められます。

| 位置 | マーク | 動作 |
|---|---|---|
| 左上 | 足 | **Steps**。止まっているときはタップで開始。計測中は画面を約 2.5 秒長押しして足マークを出し、その足を約 2 秒長押しで一時停止。止まっているときに長押しで終了し、その歩数を今日の合計へ加算（10歩=1点） |
| 右上 | カメラ | Camera ファインダー（SETTING → Sensors でカメラ Off のときは非表示）。画面タップで 3・2・1 のあと撮影。左上の戻るでホームへ |
| 左下 | 時計 | Mindful 1分タイマー |
| 右下 | ハート | Health 診断。カメラ On なら画面タップで 3・2・1 のあと顔写真。HR Sensor On なら続けて Port B で心拍を測ってから診断 |

中央のキャラをタップするとなでられます。10 回でハート +10 点（上限 20）。歩数を測っているあいだは誤タップ防止のため効きません。キャラを **3 秒以上長押し**すると、GitHub / Facebook / Instagram の QR が出ます。タップで閉じます。

### Steps（歩数）

ポケットに入れたまま歩き続けられるようにしています。

1. **開始** — ホーム左上の足、または GO の Steps をタップ
2. **計測中** — 画面全体のタップやスワイプは効かない。ポケットの押し込みでは止まらない。画面がスリープしても歩数は続く
3. **一時停止** — 画面を約 2.5 秒長押しすると左上に足マークが出る。その足を約 2 秒長押し。ポケットの押し込みでは止まらない。スリープ中も同じ（先に起こすだけで計測は続く）
4. **再開** — 一時停止中に足または GO の Steps をタップ
5. **終了** — 一時停止中に足または GO の Steps を長押し。その回の歩数を今日の合計へ加算（10歩=Health 1点）。結果は画面に残り、Health 診断でも使う

### GO（右スワイプ）

ボタンを押すとすぐ始まり、ホームへ戻ります。計測中は画面ロックのため GO へスワイプできません。一時停止してから操作します。

| ボタン | 操作 |
|---|---|
| **Steps** | 上の「Steps（歩数）」と同じ。タップで開始/再開、長押しで終了 |
| **Squats** | 胸のあたりで持つ。タップで開始/一時停止、長押しでゼロ終了。20 回で完了 |
| **HR** | SETTING → Sensors で HR Sensor が On のとき表示。Port B の心拍センサーに指をのせる。脈が取れたら BPM を表示。もう一度押すと中止 |
| **Timers** | タップして Mindful（1分）/ Stretch（3分）/ Yoga（5分）を選ぶ |
| **Camera** | SETTING → Sensors でカメラ On のとき表示。タップでファインダー。左上の戻るでホームへ。画面をもう一度タップすると、大きく 3・2・1 が出たあと撮影し、Muse が写っているものを説明 |
| **Health** | カメラ On ならファインダー → 3・2・1 → 顔写真。HR Sensor On ならそのあと Port B で心拍。最後に Muse が Good / So so / Bad と対応策を表示。どちらも Off なら活動だけから診断 |

タイマーの途中・終了は短いチャープだけ（うるさいビープは出さない）。

心拍センサーは本体右側面の **Port B**（Grove）。Unit Heart（MAX30100/MAX30102）なら I2C（G8=SDA、G9=SCL）。アナログの脈波センサーなら信号を G8 へ。

### SETTING（左スワイプ）

Wi-Fi、スリープ、**CHARACTER**（Muse / Fitin）、**Sensors** など。Sensors の中に Camera、Sound、**HR sensor**（オン/オフ）。キャラ切替はヘッダーの名前タップでもできます。カメラ Off で右上のシャッターが消える。HR sensor Off で GO の HR ボタンが消え、Health は心拍を測らない。

## ビルド

必要: ESP-IDF v6、USB 接続した M5Stack CoreS3。

```bash
# 1. Meta SDK を隣に置く（初回のみ）
git clone https://github.com/facebookincubator/muse-gadget-sdk.git ../muse-gadget-sdk

# 2. この差分を SDK に重ねる
./sync_to_sdk.sh ../muse-gadget-sdk

# 3. ビルドして書き込む
. "$HOME/esp/esp-idf-v6/export.sh"
cd ../muse-gadget-sdk/esp32
idf.py -B build-muse-m5stack-cores3 build
idf.py -B build-muse-m5stack-cores3 -p /dev/cu.usbmodem1101 flash
```

シリアルポートは環境で変わります（`ls /dev/cu.usbmodem*`）。

### SDK トークン

[gadgets.muse.ai](https://gadgets.muse.ai/settings/sdk-tokens) のトークンは **デバイスの NVS にだけ** 入れてください。リポジトリや `sdkconfig` に書かないこと。

Muse アプリ（Developer mode）から `MuseGadget` としてペアします。

## ローカルからの再同期

`../muse-gadget-sdk` で開発した変更を、この Fitingo リポジトリへ取り込む:

```bash
./sync_from_sdk.sh ../muse-gadget-sdk
```

## ライセンス

- `firmware/` のうち Meta SDK 由来のファイル: Apache-2.0（上流の著作権表示を維持）
- Fitin 向けの追加（スクワット、Health、キャラ選択など）: kfit と同じ MIT
