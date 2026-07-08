import React, { useEffect, useState } from 'react';
import { doc, getDoc } from 'firebase/firestore';
import { db } from '../services/firebase';

// 週間レポート共有カードの閲覧ページ（fit.ktrips.net/r/{shareId}）
// iOS アプリからシェアされたカードを、未ログイン・未インストールでも閲覧できる。
// アプリの外に出る最初のバイラル面（SamBezThieMuskJobs_plan P1）。

interface SharedReport {
  username: string;
  streak: number;
  weekSets: number;
  weekXP: number;
  weekLabel: string;
}

const APP_STORE_URL = 'https://apps.apple.com/jp/app/kfit-fitingo/id6746108484';

export const SharedReportView: React.FC<{ shareId: string }> = ({ shareId }) => {
  const [report, setReport] = useState<SharedReport | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    getDoc(doc(db, 'shared-reports', shareId))
      .then(snap => {
        if (snap.exists()) setReport(snap.data() as SharedReport);
      })
      .finally(() => setLoading(false));
  }, [shareId]);

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-green-500" />
      </div>
    );
  }

  if (!report) {
    return (
      <div className="min-h-screen flex flex-col items-center justify-center bg-gray-50 px-6 text-center">
        <p className="text-4xl mb-4">🔍</p>
        <p className="font-bold text-gray-700 mb-2">レポートが見つかりません</p>
        <p className="text-sm text-gray-400 mb-6">リンクの有効期限が切れたか、削除された可能性があります。</p>
        <a href="/books" className="text-sm text-green-600 underline">Fitingo について見る</a>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gray-50 flex flex-col items-center px-5 py-10">
      {/* カード */}
      <div
        className="w-full max-w-sm aspect-square rounded-3xl p-7 flex flex-col text-white shadow-2xl"
        style={{ background: 'linear-gradient(135deg, #58CC02 0%, #0A855A 100%)' }}
      >
        <div className="flex justify-between items-center">
          <span className="font-black text-lg opacity-90">Fitingo</span>
          <span className="text-sm font-bold opacity-75">{report.weekLabel}</span>
        </div>

        <div className="flex-1 flex flex-col items-center justify-center gap-2">
          <span className="text-6xl">🔥</span>
          <span className="text-5xl font-black">{report.streak}日連続</span>
          <div className="flex gap-8 mt-3">
            <div className="text-center">
              <div className="text-3xl font-black">{report.weekSets}</div>
              <div className="text-xs font-bold opacity-80">今週のセット</div>
            </div>
            <div className="text-center">
              <div className="text-3xl font-black">{report.weekXP}</div>
              <div className="text-xs font-bold opacity-80">XP</div>
            </div>
          </div>
        </div>

        <div className="text-center">
          <p className="font-bold text-sm">{report.username} は続いている。</p>
          <p className="text-xs opacity-75 mt-1">今度こそ、続く。 — fit.ktrips.net</p>
        </div>
      </div>

      {/* CTA */}
      <div className="mt-8 text-center max-w-sm">
        <p className="text-gray-700 font-bold mb-1">
          10年三日坊主でも、大丈夫。
        </p>
        <p className="text-sm text-gray-500 mb-5 leading-relaxed">
          数えるのも、記録するのも、iPhoneとApple Watchが勝手にやります。
          あなたは明日の朝、スクワット5回だけ。
        </p>
        <a
          href={APP_STORE_URL}
          target="_blank"
          rel="noopener noreferrer"
          className="inline-block bg-green-500 hover:bg-green-600 text-white font-black px-8 py-3.5 rounded-2xl shadow-lg transition-colors"
        >
          無料で始める（App Store）
        </a>
        <div className="mt-4">
          <a href="/challenge-90" className="text-sm text-green-700 underline font-semibold">
            90日再検査チャレンジを見る →
          </a>
        </div>
      </div>

      <footer className="mt-10 text-xs text-gray-400">
        © 2026 Fitingo · <a href="/books" className="underline">fit.ktrips.net</a>
      </footer>
    </div>
  );
};
