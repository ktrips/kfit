#!/usr/bin/env node
/**
 * 90秒モードの検証指標（firstSetSeconds）を全ユーザー分まとめて表示する。
 * 判定基準: docs/SamBezThieMuskJobs_plan.md — 120秒以内に1セット完了で合格。
 *
 * 実行方法:
 *   cd firebase/functions
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json node scripts/check-first-set-seconds.js
 *
 * サービスアカウントキーが無い場合は `gcloud auth application-default login` でも可
 * （Firebase プロジェクトへの Firestore 読み取り権限が必要）。
 */
const admin = require('firebase-admin');

const PASS_THRESHOLD_SECONDS = 120;

admin.initializeApp();

async function main() {
  const usersSnap = await admin.firestore().collection('users').get();

  const results = [];
  for (const userDoc of usersSnap.docs) {
    const summarySnap = await userDoc.ref.collection('retention').doc('summary').get();
    if (!summarySnap.exists) continue;
    const data = summarySnap.data();
    if (typeof data.firstSetSeconds !== 'number') continue;
    results.push({
      uid: userDoc.id,
      firstSetSeconds: data.firstSetSeconds,
      firstActiveDay: data.firstActiveDay ?? '(不明)',
    });
  }

  if (results.length === 0) {
    console.log('firstSetSeconds が記録されたユーザーはまだいません。');
    return;
  }

  results.sort((a, b) => a.firstSetSeconds - b.firstSetSeconds);

  console.log(`\n=== firstSetSeconds 計測結果（${results.length}人）===\n`);
  let passCount = 0;
  for (const r of results) {
    const pass = r.firstSetSeconds <= PASS_THRESHOLD_SECONDS;
    if (pass) passCount++;
    console.log(
      `${r.uid}  ${String(r.firstSetSeconds).padStart(4)}秒  ${pass ? '✅ 合格' : '❌ 不合格'}  (初回活動日: ${r.firstActiveDay})`
    );
  }

  const avg = results.reduce((s, r) => s + r.firstSetSeconds, 0) / results.length;
  console.log(`\n平均: ${avg.toFixed(1)}秒 / 合格率: ${passCount}/${results.length}`);
  console.log(
    passCount === results.length
      ? '\n🎉 全員120秒以内に1セット完了 → P1の正式実装判定に進めます'
      : '\n⚠️ 未達のユーザーがいます → オンボーディング導線の見直しを検討'
  );
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('❌ 実行エラー:', err.message);
    process.exit(1);
  });
