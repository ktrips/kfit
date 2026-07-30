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
//     platforms: { ios: true, web: true },  // 利用したことのあるプラットフォーム
//     firstPlatform: "ios" | "web",   // 初回活動のプラットフォーム（初回のみ設定）
//     lastPlatform:  "ios" | "web",   // 直近の活動プラットフォーム（毎回更新）
//     firstSource: string,            // 初回アクセス元の分類（初回のみ設定。下記 classifySource 参照）
//     firstReferrer: string,          // firstSource分類のもとになった生referrer/host
//     updatedAt: Timestamp
//   }
//
// 7/30/90 日継続率の定義・集計は Cloud Function（computeRetentionStats）が担い、
// クライアントは「活動した日付」という事実だけを書く。

// SNSなど既知のreferrerホストの分類テーブル
const SNS_HOSTS: Record<string, string> = {
  'x.com': 'sns:x',
  'twitter.com': 'sns:x',
  't.co': 'sns:x',
  'instagram.com': 'sns:instagram',
  'l.instagram.com': 'sns:instagram',
  'facebook.com': 'sns:facebook',
  'm.facebook.com': 'sns:facebook',
  'lm.facebook.com': 'sns:facebook',
  'line.me': 'sns:line',
  'note.com': 'sns:note',
  'threads.net': 'sns:threads',
  'l.threads.net': 'sns:threads',
  'reddit.com': 'sns:reddit',
};

// Fitingo自身のホスト（LP・シェアカードなど内部遷移を「webapp」として区別するため）
const OWN_HOSTS = ['fit.ktrips.net', 'kfitapp.web.app', 'kfitapp.firebaseapp.com'];

/**
 * document.referrer / URLクエリから初回アクセス元を分類する。
 * ページ初回ロード時（モジュール読み込み時）に一度だけ呼び、結果をキャプチャしておく。
 * SPA内遷移やhistory.replaceStateでreferrer/queryが失われた後に呼んでも意味がないため。
 */
function classifySource(): { source: string; referrer: string } {
  try {
    const params = new URLSearchParams(window.location.search);
    const utmSource = params.get('utm_source');
    if (utmSource) return { source: `utm:${utmSource}`, referrer: window.location.search };

    const referrer = document.referrer || '';
    if (!referrer) return { source: 'direct', referrer: '' };

    const host = new URL(referrer).hostname.replace(/^www\./, '');
    if (OWN_HOSTS.includes(host) || host === window.location.hostname) {
      return { source: 'webapp', referrer: host };
    }
    if (SNS_HOSTS[host]) return { source: SNS_HOSTS[host], referrer: host };
    return { source: `referral:${host}`, referrer: host };
  } catch {
    return { source: 'direct', referrer: '' };
  }
}

// ページ初回ロード時に一度だけキャプチャ（モジュールは1セッション1回だけ評価される）
const CAPTURED_SOURCE = classifySource();

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
    const data = snap.exists() ? snap.data() : undefined;
    const firstActiveDay = (data?.firstActiveDay as string | undefined) ?? today;
    const firstPlatform = (data?.firstPlatform as string | undefined) ?? 'web';
    const firstSource = (data?.firstSource as string | undefined) ?? CAPTURED_SOURCE.source;
    const firstReferrer = (data?.firstReferrer as string | undefined) ?? CAPTURED_SOURCE.referrer;
    // updateDoc はドキュメント未存在で失敗するため、先に merge で確実に作る
    await setDoc(ref, { firstActiveDay, firstPlatform, firstSource, firstReferrer }, { merge: true });
    await updateDoc(ref, {
      lastActiveDay: today,
      lastPlatform: 'web',
      totalActiveDays: increment(1),
      [`days.${today}`]: true,
      [`platforms.web`]: true,
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
