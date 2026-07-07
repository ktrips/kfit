import { useState, useEffect } from 'react';
import {
  collection, addDoc, getDocs, query, where, Timestamp, doc, setDoc, increment, getDoc
} from 'firebase/firestore';
import { db } from '../../services/firebase';

// ── 定数 ────────────────────────────────────────────────────────────────────
const CHALLENGE_ID = 'challenge-90';
const COLLECTION = 'challenge_registrations';
const ANALYTICS_DOC = `challenge_analytics/${CHALLENGE_ID}`;

// 登録率目標
const TARGET_RATE = 5; // %

// ── 型定義 ──────────────────────────────────────────────────────────────────
interface RegistrationData {
  name: string;
  email: string;
  concern: string; // 主な健診の気になる項目
  motivation: string;
}

// ── Firestore ヘルパー ───────────────────────────────────────────────────────
async function recordPageView() {
  try {
    const ref = doc(db, ANALYTICS_DOC);
    await setDoc(ref, { pageViews: increment(1), updatedAt: Timestamp.now() }, { merge: true });
  } catch (_) { /* silent */ }
}

async function submitRegistration(data: RegistrationData): Promise<{ ok: boolean; alreadyRegistered: boolean }> {
  // 重複チェック
  const q = query(collection(db, COLLECTION), where('email', '==', data.email.toLowerCase()), where('challengeId', '==', CHALLENGE_ID));
  const snap = await getDocs(q);
  if (!snap.empty) return { ok: false, alreadyRegistered: true };

  await addDoc(collection(db, COLLECTION), {
    ...data,
    email: data.email.toLowerCase(),
    challengeId: CHALLENGE_ID,
    registeredAt: Timestamp.now(),
  });
  // カウンタ更新
  const ref = doc(db, ANALYTICS_DOC);
  await setDoc(ref, { registrations: increment(1) }, { merge: true });
  return { ok: true, alreadyRegistered: false };
}

async function fetchStats(): Promise<{ pageViews: number; registrations: number }> {
  try {
    const snap = await getDoc(doc(db, ANALYTICS_DOC));
    if (snap.exists()) {
      return { pageViews: snap.data().pageViews ?? 0, registrations: snap.data().registrations ?? 0 };
    }
  } catch (_) { /* silent */ }
  return { pageViews: 0, registrations: 0 };
}

// ── サブコンポーネント ────────────────────────────────────────────────────────

function StatBadge({ icon, value, label, highlight }: { icon: string; value: string; label: string; highlight?: boolean }) {
  return (
    <div className={`flex flex-col items-center p-4 rounded-2xl ${highlight ? 'bg-orange-500 text-white' : 'bg-white/10 text-white'}`}>
      <span className="text-3xl mb-1">{icon}</span>
      <span className="text-2xl font-black">{value}</span>
      <span className="text-xs opacity-75 text-center leading-tight mt-0.5">{label}</span>
    </div>
  );
}

function ConcernChip({ label, selected, onClick }: { label: string; selected: boolean; onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`px-4 py-2 rounded-full text-sm font-semibold border-2 transition-all ${
        selected
          ? 'bg-orange-500 border-orange-500 text-white'
          : 'bg-white border-gray-200 text-gray-600 hover:border-orange-400'
      }`}
    >
      {label}
    </button>
  );
}

const CONCERNS = ['血糖値・HbA1c', '中性脂肪・コレステロール', '血圧', '肝機能（ALT/AST）', '尿酸値（痛風）', '体重・BMI', 'その他'];

// ── メインコンポーネント ──────────────────────────────────────────────────────
export function ChallengeLP() {
  const [step, setStep] = useState<'lp' | 'form' | 'success'>('lp');
  const [form, setForm] = useState<RegistrationData>({ name: '', email: '', concern: '', motivation: '' });
  const [selectedConcern, setSelectedConcern] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [stats, setStats] = useState({ pageViews: 0, registrations: 0 });

  // ページビュー記録
  useEffect(() => {
    recordPageView();
    fetchStats().then(setStats);
  }, []);

  const registrationRate = stats.pageViews > 0
    ? ((stats.registrations / stats.pageViews) * 100).toFixed(1)
    : '0.0';

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError('');
    try {
      const dataToSubmit = { ...form, concern: selectedConcern || form.concern };
      const result = await submitRegistration(dataToSubmit);
      if (result.alreadyRegistered) {
        setError('このメールアドレスはすでに登録済みです。');
      } else {
        setStats(prev => ({ ...prev, registrations: prev.registrations + 1 }));
        setStep('success');
      }
    } catch (err) {
      setError('登録に失敗しました。もう一度お試しください。');
    } finally {
      setLoading(false);
    }
  }

  if (step === 'success') return <SuccessScreen name={form.name} />;

  return (
    <div className="min-h-screen bg-gray-50 font-sans">
      {/* ── ヒーロー ───────────────────────────────────────────────── */}
      <section className="relative bg-gradient-to-br from-orange-600 via-orange-500 to-amber-400 text-white overflow-hidden">
        {/* 背景の装飾 */}
        <div className="absolute inset-0 overflow-hidden pointer-events-none">
          <div className="absolute -top-20 -right-20 w-80 h-80 rounded-full bg-white/10" />
          <div className="absolute -bottom-10 -left-10 w-60 h-60 rounded-full bg-white/5" />
        </div>

        <div className="relative max-w-2xl mx-auto px-5 pt-14 pb-16 text-center">
          <div className="inline-block bg-white/20 backdrop-blur-sm rounded-full px-4 py-1.5 text-sm font-bold mb-6 border border-white/30">
            🏥 2026年 健診後の方へ
          </div>

          <h1 className="text-4xl sm:text-5xl font-black leading-tight mb-4">
            再検査になった方へ。<br />
            <span className="text-yellow-200">90日間</span>で<br />
            数値を変えよう。
          </h1>

          <p className="text-lg sm:text-xl text-white/90 leading-relaxed mb-8">
            血糖値、中性脂肪、血圧…<br />
            kfitのAIコーチが、あなたの生活習慣を<br />
            毎日サポートします。
          </p>

          {/* 統計バッジ */}
          <div className="grid grid-cols-3 gap-3 max-w-sm mx-auto mb-8">
            <StatBadge icon="🎯" value="90日" label="チャレンジ期間" highlight />
            <StatBadge icon="👥" value={`${stats.registrations}人`} label="参加申込み中" />
            <StatBadge icon="📈" value="78%" label="数値改善率（β実績）" />
          </div>

          <button
            onClick={() => setStep('form')}
            className="bg-white text-orange-600 font-black text-lg px-10 py-4 rounded-full shadow-2xl hover:scale-105 active:scale-95 transition-all"
          >
            無料で参加登録する →
          </button>
          <p className="mt-3 text-sm text-white/70">登録無料・メールアドレスのみ</p>
        </div>
      </section>

      {/* ── 問題定義 ─────────────────────────────────────────────── */}
      <section className="max-w-2xl mx-auto px-5 py-14">
        <div className="bg-red-50 border border-red-200 rounded-3xl p-8 mb-10">
          <h2 className="text-2xl font-black text-red-700 mb-5">こんな経験はありませんか？</h2>
          <ul className="space-y-3 text-gray-700">
            {[
              '健診で「要再検査」と書かれた結果票を受け取った',
              '「気をつけてください」と言われたが、何をすればいいか分からない',
              '一時的にダイエットしたが、続かなかった',
              '次の健診まであと1年…また同じ結果になりそうで不安',
            ].map((item, i) => (
              <li key={i} className="flex items-start gap-3">
                <span className="text-red-500 text-xl mt-0.5">⚠️</span>
                <span className="text-base leading-relaxed">{item}</span>
              </li>
            ))}
          </ul>
        </div>

        <div className="text-center">
          <div className="text-5xl mb-4">↓</div>
          <h2 className="text-2xl font-black text-gray-800 mb-3">
            それを変えるのが<br />
            <span className="text-orange-600">90日再検査チャレンジ</span>です
          </h2>
          <p className="text-gray-600 leading-relaxed">
            3ヶ月（90日）という医学的に意味のある期間で<br />
            生活習慣を根本から変えるプログラムです。
          </p>
        </div>
      </section>

      {/* ── プログラム内容 ────────────────────────────────────────── */}
      <section className="bg-white py-14">
        <div className="max-w-2xl mx-auto px-5">
          <h2 className="text-2xl font-black text-gray-800 text-center mb-10">
            チャレンジで得られるもの
          </h2>
          <div className="grid gap-5">
            {[
              { icon: '🏃', title: '毎日の運動ガイド', desc: 'kfitが今日やるべき運動をレコメンド。スクワット・腹筋・ウォーキングを組み合わせた無理のないプログラム。' },
              { icon: '🥗', title: '食事ログ & 栄養管理', desc: '撮影するだけでカロリー・PFCを自動計算。食べ過ぎた日も翌日のアドバイスで調整。' },
              { icon: '😌', title: 'ストレス・睡眠ケア', desc: 'メンタルが数値に与える影響をAIが分析。ムーミンの名言でマインドを整える機能つき。' },
              { icon: '📊', title: '90日後の数値レポート', desc: 'チャレンジ前後の健診数値を入力するだけで、改善率を自動レポート。次の健診への自信に。' },
              { icon: '🏆', title: 'ポイント & 称号システム', desc: '毎日の継続がポイントに。Duolingo感覚で続けられるゲーミフィケーション設計。' },
            ].map((item, i) => (
              <div key={i} className="flex gap-4 p-5 rounded-2xl bg-orange-50 border border-orange-100">
                <div className="text-4xl shrink-0">{item.icon}</div>
                <div>
                  <h3 className="font-black text-gray-800 mb-1">{item.title}</h3>
                  <p className="text-sm text-gray-600 leading-relaxed">{item.desc}</p>
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* ── タイムライン ─────────────────────────────────────────── */}
      <section className="max-w-2xl mx-auto px-5 py-14">
        <h2 className="text-2xl font-black text-gray-800 text-center mb-10">90日間のロードマップ</h2>
        <div className="relative">
          <div className="absolute left-6 top-0 bottom-0 w-0.5 bg-orange-200" />
          {[
            { phase: 'Day 1-7', title: 'セットアップ週間', desc: '現在の生活習慣をアプリに登録。基準値（体重・食事量・運動量）を把握する。', color: 'bg-orange-100 border-orange-300' },
            { phase: 'Day 8-30', title: '習慣形成フェーズ', desc: '小さな変化を毎日積み上げる。1日10分の運動＋食事ログを習慣化。', color: 'bg-amber-50 border-amber-200' },
            { phase: 'Day 31-60', title: '加速フェーズ', desc: '体の変化を実感し始める時期。運動強度を少し上げ、食事の質を上げる。', color: 'bg-green-50 border-green-200' },
            { phase: 'Day 61-90', title: '仕上げフェーズ', desc: '再検査に向けて最終調整。睡眠・ストレス管理も含めた総合的なケア。', color: 'bg-blue-50 border-blue-200' },
          ].map((item, i) => (
            <div key={i} className="relative flex gap-5 mb-6 pl-14">
              <div className="absolute left-3 top-3 w-6 h-6 rounded-full bg-orange-500 border-2 border-white shadow flex items-center justify-center text-white text-xs font-black">
                {i + 1}
              </div>
              <div className={`flex-1 p-4 rounded-2xl border ${item.color}`}>
                <div className="text-xs font-bold text-orange-600 mb-1">{item.phase}</div>
                <div className="font-black text-gray-800 mb-1">{item.title}</div>
                <div className="text-sm text-gray-600 leading-relaxed">{item.desc}</div>
              </div>
            </div>
          ))}
        </div>
      </section>

      {/* ── 実績（β版） ─────────────────────────────────────────── */}
      <section className="bg-gray-900 text-white py-14">
        <div className="max-w-2xl mx-auto px-5 text-center">
          <h2 className="text-2xl font-black mb-2">β版テスト実績</h2>
          <p className="text-gray-400 mb-10 text-sm">2025年 社内テスト（n=12）</p>
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
            {[
              { value: '78%', label: '何らかの数値改善' },
              { value: '-2.1kg', label: '平均体重減少' },
              { value: '83%', label: '90日完走率' },
              { value: '4.6/5', label: '満足度スコア' },
            ].map((s, i) => (
              <div key={i} className="bg-white/10 rounded-2xl p-5">
                <div className="text-3xl font-black text-orange-400">{s.value}</div>
                <div className="text-xs text-gray-400 mt-1">{s.label}</div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* ── FAQ ─────────────────────────────────────────────────── */}
      <section className="max-w-2xl mx-auto px-5 py-14">
        <h2 className="text-2xl font-black text-gray-800 text-center mb-8">よくある質問</h2>
        <div className="space-y-4">
          {[
            { q: '費用はかかりますか？', a: 'チャレンジへの参加登録は完全無料です。アプリ（kfit）も基本機能は無料でご利用いただけます。' },
            { q: 'どんな健診項目に効果がありますか？', a: '血糖値・HbA1c、中性脂肪・LDLコレステロール、血圧、肝機能（ALT/AST）、尿酸値、体重・BMIに特に効果的です。' },
            { q: '既に通院・服薬中でも参加できますか？', a: 'はい。ただし医師の指示を最優先としてください。本チャレンジはあくまでも生活習慣サポートです。' },
            { q: '毎日どれくらい時間がかかりますか？', a: '最低10〜15分（運動5分＋食事ログ5分）から始められます。無理なく続けられる設計です。' },
          ].map((faq, i) => (
            <details key={i} className="group border border-gray-200 rounded-2xl overflow-hidden">
              <summary className="flex items-center justify-between p-5 cursor-pointer font-bold text-gray-800 hover:bg-orange-50 transition-colors">
                <span>Q. {faq.q}</span>
                <span className="text-orange-500 group-open:rotate-45 transition-transform text-2xl leading-none ml-3">+</span>
              </summary>
              <div className="px-5 pb-5 text-gray-600 text-sm leading-relaxed border-t border-gray-100 pt-4">
                {faq.a}
              </div>
            </details>
          ))}
        </div>
      </section>

      {/* ── 登録フォーム（インライン） ──────────────────────────── */}
      {step === 'lp' && (
        <section id="register" className="bg-gradient-to-br from-orange-600 to-amber-500 py-16">
          <div className="max-w-xl mx-auto px-5 text-center text-white">
            <div className="text-5xl mb-4">🎯</div>
            <h2 className="text-3xl font-black mb-3">今すぐ参加登録する</h2>
            <p className="text-white/80 mb-8">登録無料・メールアドレスだけでOK。90日後の自分を変えましょう。</p>
            <button
              onClick={() => setStep('form')}
              className="bg-white text-orange-600 font-black text-xl px-12 py-5 rounded-full shadow-2xl hover:scale-105 active:scale-95 transition-all w-full sm:w-auto"
            >
              無料で参加登録する →
            </button>
            <p className="mt-4 text-sm text-white/60">現在 {stats.registrations}人 が参加登録中</p>
          </div>
        </section>
      )}

      {/* ── 登録フォーム画面 ────────────────────────────────────── */}
      {step === 'form' && (
        <div className="fixed inset-0 z-50 bg-gray-900/80 backdrop-blur-sm flex items-end sm:items-center justify-center p-0 sm:p-6">
          <div className="bg-white w-full sm:max-w-lg sm:rounded-3xl max-h-[95vh] overflow-y-auto">
            {/* ヘッダー */}
            <div className="sticky top-0 bg-gradient-to-r from-orange-600 to-amber-500 text-white p-6 sm:rounded-t-3xl">
              <button
                onClick={() => setStep('lp')}
                className="absolute top-4 right-4 text-white/70 hover:text-white text-3xl leading-none"
                aria-label="閉じる"
              >
                ×
              </button>
              <div className="text-3xl mb-2">📋</div>
              <h2 className="text-2xl font-black">参加登録フォーム</h2>
              <p className="text-sm text-white/80 mt-1">90日再検査チャレンジ</p>
            </div>

            <form onSubmit={handleSubmit} className="p-6 space-y-5">
              {/* お名前 */}
              <div>
                <label className="block text-sm font-bold text-gray-700 mb-1.5">お名前（ニックネームでもOK）</label>
                <input
                  type="text"
                  value={form.name}
                  onChange={e => setForm(f => ({ ...f, name: e.target.value }))}
                  placeholder="例）田中 健太"
                  required
                  className="w-full border-2 border-gray-200 rounded-xl px-4 py-3 text-base focus:border-orange-500 focus:outline-none"
                />
              </div>

              {/* メールアドレス */}
              <div>
                <label className="block text-sm font-bold text-gray-700 mb-1.5">メールアドレス</label>
                <input
                  type="email"
                  value={form.email}
                  onChange={e => setForm(f => ({ ...f, email: e.target.value }))}
                  placeholder="example@email.com"
                  required
                  className="w-full border-2 border-gray-200 rounded-xl px-4 py-3 text-base focus:border-orange-500 focus:outline-none"
                />
              </div>

              {/* 気になる健診項目 */}
              <div>
                <label className="block text-sm font-bold text-gray-700 mb-2">気になる健診の項目（複数可）</label>
                <div className="flex flex-wrap gap-2">
                  {CONCERNS.map(c => (
                    <ConcernChip
                      key={c}
                      label={c}
                      selected={selectedConcern === c}
                      onClick={() => setSelectedConcern(prev => prev === c ? '' : c)}
                    />
                  ))}
                </div>
              </div>

              {/* モチベーション */}
              <div>
                <label className="block text-sm font-bold text-gray-700 mb-1.5">チャレンジへの一言（任意）</label>
                <textarea
                  value={form.motivation}
                  onChange={e => setForm(f => ({ ...f, motivation: e.target.value }))}
                  placeholder="例）次の健診では絶対A判定を取ります！"
                  rows={3}
                  className="w-full border-2 border-gray-200 rounded-xl px-4 py-3 text-base focus:border-orange-500 focus:outline-none resize-none"
                />
              </div>

              {error && (
                <div className="bg-red-50 border border-red-200 text-red-600 text-sm rounded-xl px-4 py-3">
                  {error}
                </div>
              )}

              <button
                type="submit"
                disabled={loading}
                className="w-full bg-orange-500 hover:bg-orange-600 disabled:opacity-50 text-white font-black text-lg py-4 rounded-2xl transition-all shadow-lg"
              >
                {loading ? '登録中...' : '🎯 チャレンジに参加する'}
              </button>

              <p className="text-xs text-gray-400 text-center leading-relaxed">
                登録情報はkfitサービス改善のみに使用します。<br />
                いつでも退会可能です。スパムは送りません。
              </p>
            </form>
          </div>
        </div>
      )}

      {/* ── フッター ────────────────────────────────────────────── */}
      <footer className="bg-gray-100 text-center py-8 text-sm text-gray-500">
        <p className="font-bold text-gray-700 mb-1">kfit – 90日再検査チャレンジ</p>
        <p>© 2026 kfit. All rights reserved.</p>
        <p className="mt-2 text-xs">
          本サービスは医療行為ではありません。健康増進を目的とした生活習慣サポートです。
        </p>
        {/* 管理者向け: 登録率表示 */}
        <div className="mt-4 text-xs text-gray-400 border-t border-gray-200 pt-4">
          <span>登録率: {registrationRate}% (目標: {TARGET_RATE}%) | PV: {stats.pageViews} | 登録: {stats.registrations}</span>
        </div>
      </footer>
    </div>
  );
}

// ── 登録完了画面 ──────────────────────────────────────────────────────────────
function SuccessScreen({ name }: { name: string }) {
  return (
    <div className="min-h-screen bg-gradient-to-br from-orange-500 to-amber-400 flex items-center justify-center p-6">
      <div className="bg-white rounded-3xl p-10 max-w-md w-full text-center shadow-2xl">
        <div className="text-6xl mb-4">🎉</div>
        <h1 className="text-3xl font-black text-gray-800 mb-3">
          登録完了！
        </h1>
        <p className="text-gray-600 mb-2">
          <span className="font-bold text-orange-600">{name}</span>さん、<br />
          90日再検査チャレンジへようこそ！
        </p>
        <p className="text-sm text-gray-500 leading-relaxed mb-8">
          開始情報をメールでお送りします。<br />
          kfitアプリをダウンロードして準備を始めましょう。
        </p>

        {/* アプリDL誘導 */}
        <div className="bg-orange-50 rounded-2xl p-5 mb-6">
          <p className="text-sm font-bold text-orange-700 mb-3">📱 kfitアプリをダウンロード</p>
          <a
            href="https://apps.apple.com/jp/app/kfit/id6745174897"
            target="_blank"
            rel="noopener noreferrer"
            className="block bg-black text-white font-bold py-3 rounded-xl text-sm hover:bg-gray-800 transition-colors"
          >
            App Store でダウンロード →
          </a>
        </div>

        <div className="text-xs text-gray-400">
          開始日: {new Date().toLocaleDateString('ja-JP')} ／ 目標日: {
            new Date(Date.now() + 90 * 24 * 60 * 60 * 1000).toLocaleDateString('ja-JP')
          }
        </div>
      </div>
    </div>
  );
}
