---
name: plan-status
description: SamBezThieMuskJobs_plan（統合戦略プラン）の実施状況ダッシュボードを表示・更新する。kfit の戦略施策（90秒モード・継続コホート・共有カード・AIプロキシ等）の進捗確認に使う。
---

# plan-status: 戦略プラン実施状況の表示・更新

docs/SamBezThieMuskJobs_plan.md の「実施状況ダッシュボード」セクションを表示し、
コードベースの実態と突き合わせて更新する。

## 手順

### 1. 現在のダッシュボードを表示

「## 実施状況ダッシュボード」〜次の `---` までを読み、そのままユーザーに提示する。

### 2. 実態との突き合わせ（表示だけでなく検証する）

各ステータスを鵜呑みにせず、以下で裏を取る:

| 施策 | 確認方法 |
|---|---|
| /release-check・/port-feature skill | `ls .claude/skills/` |
| 継続コホート計測 | `grep -l RetentionTracker ios/kfit/Managers/` + `grep computeRetentionStats firebase/functions/index.js` |
| aiProxy | `grep aiProxy firebase/functions/index.js` |
| 90秒モード | `grep NinetySecondModeView ios/kfit/kfitApp.swift` |
| 週次共有カード | `ls ios/kfit/Views/WeeklyReportView.swift web/src/components/SharedReportView.tsx` |
| MIND 部分開放 | `grep plusLockedPreview ios/kfit/Views/MindView.swift` |
| ストア文言 | `grep "今度こそ" docs/appstore_metadata.md` |
| デプロイ状況 | ユーザーに確認（`firebase deploy` はローカルから実施） |

### 3. ダッシュボードの更新

差分があれば docs/SamBezThieMuskJobs_plan.md の該当行を更新し、
「最終更新」日付を今日に変更する。凡例: ✅完了 / 🚧実装済み・展開待ち / ⬜未着手。

### 4. 「次のアクション」の並べ替え

完了したものを除き、判断基準（同ドキュメント Part 6 末尾の 5 項目）に照らして
最も進捗が詰まっている順に並べ替える。

## 運用ルール

- kfit の戦略・施策に関わる作業をした日は、セッションの終わりにこのスキルを実行して
  ダッシュボードを最新化する
- ステータスを変えたらコミットに含める（ドキュメントと実態のズレが最大の敵）
