# Fitin on M5Stack CoreS3

Fitingo のマスコット **Fitin（フィッティン）** を、M5Stack CoreS3 上の Muse ガジェットとして動かすファームウェア差分です。

ベースは Meta の [muse-gadget-sdk](https://github.com/facebookincubator/muse-gadget-sdk)（Apache-2.0）。このフォルダは **Fitin 用の上書きファイルだけ** を持ちます。SDK 本体や SDK トークンは含めません。

## できること

- キャラ選択: **Muse** / **Fitin**（SETTING）
- 右スワイプの GO: スクワット、歩数、瞑想1分、ストレッチ3分、ヨガ5分、Health
- BMI270 でスクワット 20 回完了、歩数の開始/一時停止/長押しリセット
- Health ポイント（スクワット・歩数・タイマー・10回なでる）
- 1日 60 点以上で達成、連続日数 `H94(D1)` をヘッダーに表示。タップで Health チェック
- ホーム準備完了時は `READY` ではなく **Muse** / **Fitin**
- 日付・時刻・Wi-Fi・バッテリーはヘッダー右詰め

CoreS3 に振動モーターはないため、うるさいスピーカーランブルは出さず、完了時などは短い可愛いチャープだけにしています。

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
