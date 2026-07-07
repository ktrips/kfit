import {
  doc,
  getDoc,
  setDoc,
  updateDoc,
  increment,
  serverTimestamp,
} from 'firebase/firestore';
import { db } from './firebase';
import { localDateKey } from '../utils/date';

// 継続コホート計測（iOS の RetentionTracker.swift と同一スキーマ）
//
//   users/{uid}/retention/summary {
//     firstActiveDay: "yyyy-MM-dd",   // 初回活動日（コホートキー）
//     lastActiveDay:  "yyyy-MM-dd",
//     totalActiveDays: number,        // 参考値（集計は days マップから行う）
//     days: { "yyyy-MM-dd": true },   // 活動日マップ
//     updatedAt: Timestamp
//   }
//
// 7/30/90 日継続率の定義・集計は Cloud Function（computeRetentionStats）が担い、
// クライアントは「活動した日付」という事実だけを書く。

/** 今日を「活動あり」としてマークする（1 日 1 回・失敗時は次回再試行） */
export async function markActiveToday(userId: string): Promise<void> {
  const today = localDateKey();
  const storageKey = `retention.lastMarkedDay.${userId}`;
  try {
    if (localStorage.getItem(storageKey) === today) return;
  } catch {
    // localStorage 不可の環境では毎回書く（days マップは冪等）
  }

  const ref = doc(db, 'users', userId, 'retention', 'summary');
  try {
    const snap = await getDoc(ref);
    const firstActiveDay =
      (snap.exists() ? (snap.data().firstActiveDay as string | undefined) : undefined) ?? today;
    // updateDoc はドキュメント未存在で失敗するため、先に merge で確実に作る
    await setDoc(ref, { firstActiveDay }, { merge: true });
    await updateDoc(ref, {
      lastActiveDay: today,
      totalActiveDays: increment(1),
      [`days.${today}`]: true,
      updatedAt: serverTimestamp(),
    });
    try { localStorage.setItem(storageKey, today); } catch { /* noop */ }
  } catch (e) {
    console.warn('[retention] mark failed:', e);
  }
}

export interface RetentionStat {
  eligible: number;
  reached: number;
  rate: number | null; // % （母数不足時は null）
}

export interface PublicRetentionStats {
  d7?: RetentionStat;
  d30?: RetentionStat;
  d90?: RetentionStat;
  computedAt?: unknown;
}

/** 公開継続率統計（public-stats/retention、未集計なら null） */
export async function getPublicRetentionStats(): Promise<PublicRetentionStats | null> {
  try {
    const snap = await getDoc(doc(db, 'public-stats', 'retention'));
    return snap.exists() ? (snap.data() as PublicRetentionStats) : null;
  } catch {
    return null;
  }
}
