import React, { useEffect, useState } from 'react';
import {
  type AIProvider, type AISettings,
  getAISettings, saveAISettings, clearAISettings,
  PROVIDER_LABELS, DEFAULT_MODELS,
} from '../services/aiService';

// ── 型定義 ──────────────────────────────────────────────────────────────────

interface ReminderItem {
  id: string;
  label: string;
  description: string;
  emoji: string;
  defaultHour: number;
  defaultMinute: number;
}

interface ReminderSetting {
  enabled: boolean;
  hour: number;
  minute: number;
}

interface AppSettings {
  reminders: Record<string, ReminderSetting>;
  watchAutoLaunch: boolean;
  linkedApps: {
    duolingo: boolean;
    anyFitness: boolean;
  };
}

// ── デフォルト設定（iOS NotificationManager と同じタイミング）────────────────

const REMINDER_ITEMS: ReminderItem[] = [
  {
    id: 'amReminder',
    label: '朝のリマインダー',
    description: '朝トレを始めるタイミングで通知',
    emoji: '🌅',
    defaultHour: 6,
    defaultMinute: 0,
  },
  {
    id: 'amFollowup',
    label: '朝のフォローアップ',
    description: '朝トレをまだしていない場合に再通知',
    emoji: '🔥',
    defaultHour: 8,
    defaultMinute: 0,
  },
  {
    id: 'pmReminder',
    label: '夕方のリマインダー',
    description: '2セット目のタイミングで通知',
    emoji: '🌆',
    defaultHour: 18,
    defaultMinute: 0,
  },
  {
    id: 'pmFollowup',
    label: '夕方のフォローアップ',
    description: '夜トレをまだしていない場合に再通知',
    emoji: '⚡',
    defaultHour: 20,
    defaultMinute: 0,
  },
  {
    id: 'streakAlert',
    label: 'ストリーク警告',
    description: 'その日まだ記録がない場合に最終警告',
    emoji: '🚨',
    defaultHour: 22,
    defaultMinute: 0,
  },
];

const SETTINGS_KEY = 'duofit_settings';

function buildDefaults(): AppSettings {
  const reminders: Record<string, ReminderSetting> = {};
  REMINDER_ITEMS.forEach(item => {
    reminders[item.id] = {
      enabled: true,
      hour: item.defaultHour,
      minute: item.defaultMinute,
    };
  });
  return {
    reminders,
    watchAutoLaunch: true,
    linkedApps: { duolingo: false, anyFitness: false },
  };
}

function loadSettings(): AppSettings {
  try {
    const raw = localStorage.getItem(SETTINGS_KEY);
    if (!raw) return buildDefaults();
    return { ...buildDefaults(), ...JSON.parse(raw) };
  } catch {
    return buildDefaults();
  }
}

function saveSettings(s: AppSettings) {
  localStorage.setItem(SETTINGS_KEY, JSON.stringify(s));
}

// ── ブラウザ通知スケジューラ ────────────────────────────────────────────────

const timers: Record<string, ReturnType<typeof setTimeout>> = {};

function cancelAllTimers() {
  Object.values(timers).forEach(clearTimeout);
  Object.keys(timers).forEach(k => delete timers[k]);
}

function scheduleReminders(settings: AppSettings) {
  cancelAllTimers();
  if (Notification.permission !== 'granted') return;

  REMINDER_ITEMS.forEach(item => {
    const cfg = settings.reminders[item.id];
    if (!cfg?.enabled) return;

    const now = new Date();
    const target = new Date();
    target.setHours(cfg.hour, cfg.minute, 0, 0);
    if (target <= now) target.setDate(target.getDate() + 1);
    const delay = target.getTime() - now.getTime();

    const messages: Record<string, { title: string; body: string }> = {
      amReminder:  { title: '💪 おはよう！朝トレの時間',       body: '今日も一緒に始めよう。ストリーク継続中！' },
      amFollowup:  { title: '🔥 まだ間に合う！朝トレしよう',   body: '数分でOK。ストリークを守ろう💪' },
      pmReminder:  { title: '🌆 夕方トレーニングの時間',       body: '今日の2セット目を記録しよう！' },
      pmFollowup:  { title: '⚡ 夜トレまだ間に合う！',         body: '22時までに記録してストリークを守ろう🔥' },
      streakAlert: { title: '🚨 ストリークが途絶えそう！',     body: '今日はまだトレーニングしていません。今すぐ記録しよう！' },
    };

    const msg = messages[item.id];
    timers[item.id] = setTimeout(() => {
      new Notification(msg.title, { body: msg.body, icon: '/mascot.png' });
      // 翌日も同じ時刻に再スケジュール
      scheduleReminders(loadSettings());
    }, delay);
  });
}

function pad2(n: number) { return String(n).padStart(2, '0'); }
function toTimeStr(h: number, m: number) { return `${pad2(h)}:${pad2(m)}`; }
function fromTimeStr(s: string) {
  const [h, m] = s.split(':').map(Number);
  return { hour: h ?? 0, minute: m ?? 0 };
}

// ── Toggle コンポーネント ────────────────────────────────────────────────────

const Toggle: React.FC<{
  checked: boolean;
  onChange: (v: boolean) => void;
  disabled?: boolean;
}> = ({ checked, onChange, disabled }) => (
  <button
    role="switch"
    aria-checked={checked}
    onClick={() => !disabled && onChange(!checked)}
    disabled={disabled}
    className="relative w-12 h-6 rounded-full transition-all duration-200 focus:outline-none shrink-0"
    style={{
      background: checked ? '#58CC02' : '#d1d5db',
      boxShadow: checked ? '0 2px 0 #46A302' : '0 2px 0 #9ca3af',
      opacity: disabled ? 0.45 : 1,
    }}
  >
    <span
      className="absolute top-0.5 w-5 h-5 rounded-full bg-white shadow transition-all duration-200"
      style={{ left: checked ? '26px' : '2px' }}
    />
  </button>
);

// ── メインコンポーネント ─────────────────────────────────────────────────────

export const SettingsView: React.FC = () => {
  const [settings, setSettings] = useState<AppSettings>(buildDefaults);
  const [permStatus, setPermStatus] = useState<NotificationPermission>('default');
  const [saved, setSaved] = useState(false);

  // ── AI 設定 ──────────────────────────────────────────────────────────────────
  const [aiProvider, setAiProvider] = useState<AIProvider>('openai');
  const [aiApiKey, setAiApiKey] = useState('');
  const [aiModel, setAiModel] = useState('');
  const [aiKeyVisible, setAiKeyVisible] = useState(false);
  const [aiSaved, setAiSaved] = useState(false);

  useEffect(() => {
    setSettings(loadSettings());
    if ('Notification' in window) setPermStatus(Notification.permission);
    // AI 設定を読み込み
    const ai = getAISettings();
    if (ai) {
      setAiProvider(ai.provider);
      setAiApiKey(ai.apiKey);
      setAiModel(ai.model ?? '');
    }
  }, []);

  const handleAiSave = () => {
    if (!aiApiKey.trim()) return;
    const settings: AISettings = {
      provider: aiProvider,
      apiKey: aiApiKey.trim(),
      ...(aiModel.trim() ? { model: aiModel.trim() } : {}),
    };
    saveAISettings(settings);
    setAiSaved(true);
    setTimeout(() => setAiSaved(false), 2000);
  };

  const handleAiClear = () => {
    clearAISettings();
    setAiApiKey('');
    setAiModel('');
  };

  const handleSave = () => {
    saveSettings(settings);
    if (permStatus === 'granted') scheduleReminders(settings);
    setSaved(true);
    setTimeout(() => setSaved(false), 2000);
  };

  const requestPermission = async () => {
    if (!('Notification' in window)) return;
    const result = await Notification.requestPermission();
    setPermStatus(result);
    if (result === 'granted') scheduleReminders(settings);
  };

  const testNotification = () => {
    if (permStatus !== 'granted') return;
    new Notification('💪 DuoFit テスト通知', {
      body: '通知は正常に動作しています！',
      icon: '/mascot.png',
    });
  };

  const setReminder = (id: string, patch: Partial<ReminderSetting>) => {
    setSettings(s => ({
      ...s,
      reminders: { ...s.reminders, [id]: { ...s.reminders[id], ...patch } },
    }));
  };

  const notSupported = !('Notification' in window);

  return (
    <div className="min-h-screen bg-duo-gray-light pb-10">
      <div className="max-w-md mx-auto px-4 pt-6 space-y-5">

        {/* Header */}
        <div className="flex items-center gap-3 mb-2">
          <img src="/mascot.png" alt="" className="w-12 h-12 rounded-full object-cover shrink-0" />
          <div>
            <h2 className="text-2xl font-black text-duo-dark">設定</h2>
            <p className="text-duo-gray font-bold text-sm">通知・連動起動のカスタマイズ</p>
          </div>
        </div>

        {/* ── 通知権限バナー ─────────────────────────────── */}
        {notSupported ? (
          <div className="rounded-2xl px-4 py-3 flex items-center gap-3"
            style={{ background: '#FFF3E0', border: '2px solid #FF9600' }}>
            <span className="text-xl">⚠️</span>
            <p className="font-bold text-sm" style={{ color: '#8a4700' }}>
              このブラウザはWeb通知に対応していません
            </p>
          </div>
        ) : permStatus === 'denied' ? (
          <div className="rounded-2xl px-4 py-3 flex items-center gap-3"
            style={{ background: '#FCE4EC', border: '2px solid #FF4B4B' }}>
            <span className="text-xl">🚫</span>
            <p className="font-bold text-sm" style={{ color: '#7f0000' }}>
              通知がブロックされています。ブラウザの設定から許可してください。
            </p>
          </div>
        ) : permStatus === 'default' ? (
          <button
            onClick={requestPermission}
            className="duo-btn-primary w-full text-base py-4"
          >
            🔔 ブラウザ通知を有効にする
          </button>
        ) : (
          <div className="rounded-2xl px-4 py-3 flex items-center justify-between"
            style={{ background: '#D7FFB8', border: '2px solid #58CC02' }}>
            <div className="flex items-center gap-2">
              <span className="text-xl">✅</span>
              <p className="font-extrabold text-sm text-duo-green">通知が有効です</p>
            </div>
            <button
              onClick={testNotification}
              className="text-xs font-bold underline"
              style={{ color: '#46A302' }}
            >
              テスト送信
            </button>
          </div>
        )}

        {/* ── リマインダー設定 ─────────────────────────── */}
        <div className="duo-card overflow-hidden">
          <div className="px-5 pt-5 pb-3 border-b border-gray-100">
            <p className="font-black text-duo-dark text-base">🔔 リマインダー</p>
            <p className="text-duo-gray font-bold text-xs mt-0.5">
              通知する時間と有効/無効を設定
            </p>
          </div>

          <div className="divide-y divide-gray-100">
            {REMINDER_ITEMS.map(item => {
              const cfg = settings.reminders[item.id] ?? {
                enabled: true,
                hour: item.defaultHour,
                minute: item.defaultMinute,
              };
              return (
                <div key={item.id} className="px-5 py-4">
                  <div className="flex items-center justify-between gap-3">
                    <div className="flex items-center gap-3 flex-1 min-w-0">
                      <span className="text-xl shrink-0">{item.emoji}</span>
                      <div className="min-w-0">
                        <p className="font-extrabold text-duo-dark text-sm truncate">{item.label}</p>
                        <p className="text-duo-gray font-bold text-xs truncate">{item.description}</p>
                      </div>
                    </div>
                    <Toggle
                      checked={cfg.enabled}
                      onChange={v => setReminder(item.id, { enabled: v })}
                    />
                  </div>

                  {/* 時刻ピッカー（有効時のみ表示） */}
                  {cfg.enabled && (
                    <div className="mt-3 flex items-center gap-3">
                      <p className="text-duo-gray font-bold text-xs w-8">時刻</p>
                      <input
                        type="time"
                        value={toTimeStr(cfg.hour, cfg.minute)}
                        onChange={e => {
                          const { hour, minute } = fromTimeStr(e.target.value);
                          setReminder(item.id, { hour, minute });
                        }}
                        className="rounded-xl px-3 py-1.5 font-extrabold text-sm outline-none"
                        style={{
                          border: '2px solid #58CC02',
                          color: '#2d7a00',
                          background: '#F0FFF0',
                        }}
                      />
                      <p className="text-duo-gray font-bold text-xs">
                        毎日 {pad2(cfg.hour)}:{pad2(cfg.minute)} に通知
                      </p>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </div>

        {/* ── 連動起動設定 ────────────────────────────────── */}
        <div className="duo-card overflow-hidden">
          <div className="px-5 pt-5 pb-3 border-b border-gray-100">
            <p className="font-black text-duo-dark text-base">📱 連動起動</p>
            <p className="text-duo-gray font-bold text-xs mt-0.5">
              他のアプリや操作と連動してDuoFitを起動
            </p>
          </div>

          <div className="divide-y divide-gray-100">
            {/* Apple Watch 自動起動 */}
            <div className="px-5 py-4">
              <div className="flex items-center justify-between gap-3">
                <div className="flex items-center gap-3 flex-1 min-w-0">
                  <span className="text-2xl shrink-0">⌚</span>
                  <div className="min-w-0">
                    <p className="font-extrabold text-duo-dark text-sm">Apple Watch 自動起動</p>
                    <p className="text-duo-gray font-bold text-xs">
                      iOSアプリを開くと同時にWatchのワークアウトを開始
                    </p>
                  </div>
                </div>
                <Toggle
                  checked={settings.watchAutoLaunch}
                  onChange={v => setSettings(s => ({ ...s, watchAutoLaunch: v }))}
                />
              </div>
              <div className="mt-2 rounded-xl px-3 py-2 flex items-start gap-2"
                style={{ background: '#E3F2FD', border: '1px solid #1CB0F6' }}>
                <span className="text-xs mt-0.5">ℹ️</span>
                <p className="text-xs font-bold" style={{ color: '#0a6c96' }}>
                  iOSアプリがフォアグラウンドになるたびにWatchへシグナルを送ります。Watch側はアプリが起動済みのとき自動でワークアウト画面へ遷移します。
                </p>
              </div>
            </div>

            {/* Duolingo 連動 */}
            <div className="px-5 py-4">
              <div className="flex items-center justify-between gap-3">
                <div className="flex items-center gap-3 flex-1 min-w-0">
                  <span className="text-2xl shrink-0">🦉</span>
                  <div className="min-w-0">
                    <p className="font-extrabold text-duo-dark text-sm">Duolingo と連動</p>
                    <p className="text-duo-gray font-bold text-xs">
                      Duolingoを開いたときにDuoFitも通知で促す
                    </p>
                  </div>
                </div>
                <Toggle
                  checked={settings.linkedApps.duolingo}
                  onChange={v =>
                    setSettings(s => ({
                      ...s,
                      linkedApps: { ...s.linkedApps, duolingo: v },
                    }))
                  }
                />
              </div>
              {settings.linkedApps.duolingo && (
                <div className="mt-2 rounded-xl px-3 py-2 flex items-start gap-2"
                  style={{ background: '#FFF8E1', border: '1px solid #FFD900' }}>
                  <span className="text-xs mt-0.5">💡</span>
                  <p className="text-xs font-bold" style={{ color: '#7a5800' }}>
                    iOSのショートカットAppで「Duolingoを開く → DuoFitを開く」の自動化を設定してください。iOS設定画面で案内します。
                  </p>
                </div>
              )}
            </div>

            {/* フィットネスアプリ連動 */}
            <div className="px-5 py-4">
              <div className="flex items-center justify-between gap-3">
                <div className="flex items-center gap-3 flex-1 min-w-0">
                  <span className="text-2xl shrink-0">🏃</span>
                  <div className="min-w-0">
                    <p className="font-extrabold text-duo-dark text-sm">フィットネスアプリと連動</p>
                    <p className="text-duo-gray font-bold text-xs">
                      ヘルスケア・フィットネス系アプリを開いたとき通知
                    </p>
                  </div>
                </div>
                <Toggle
                  checked={settings.linkedApps.anyFitness}
                  onChange={v =>
                    setSettings(s => ({
                      ...s,
                      linkedApps: { ...s.linkedApps, anyFitness: v },
                    }))
                  }
                />
              </div>
            </div>
          </div>
        </div>

        {/* ── iOS ショートカット案内（連動系が1つでもONなら表示）─── */}
        {(settings.linkedApps.duolingo || settings.linkedApps.anyFitness) && (
          <div
            className="rounded-2xl p-4"
            style={{ background: 'linear-gradient(135deg, #E8F5E9 0%, #E3F2FD 100%)', border: '2px solid rgba(88,204,2,0.3)' }}
          >
            <p className="font-extrabold text-duo-dark text-sm mb-2">📲 iOSショートカット設定方法</p>
            <ol className="space-y-1.5">
              {[
                'iPhoneの「ショートカット」アプリを開く',
                '「オートメーション」タブ → 「＋」をタップ',
                '「App」を選択 → 連動したいアプリを選ぶ',
                '「開いたとき」を選択して次へ',
                '「アクションを追加」→「URLを開く」→ duofit:// を入力',
                '「完了」で保存',
              ].map((step, i) => (
                <li key={i} className="flex items-start gap-2">
                  <span
                    className="w-5 h-5 rounded-full flex items-center justify-center text-xs font-black shrink-0 mt-0.5"
                    style={{ background: '#58CC02', color: 'white' }}
                  >
                    {i + 1}
                  </span>
                  <p className="text-duo-dark font-bold text-xs">{step}</p>
                </li>
              ))}
            </ol>
          </div>
        )}

        {/* ── AI アシスタント設定 ─────────────────────────────── */}
        <div className="duo-card overflow-hidden">
          <div className="px-5 pt-5 pb-3 flex items-center gap-3 border-b border-gray-100">
            <span className="text-2xl">🤖</span>
            <div>
              <p className="font-extrabold text-duo-dark text-base">AI アシスタント</p>
              <p className="text-duo-gray font-bold text-xs">プラン自動生成に使用する AI を設定</p>
            </div>
          </div>

          <div className="px-5 py-4 space-y-4">
            {/* プロバイダー選択 */}
            <div>
              <p className="font-extrabold text-duo-dark text-sm mb-2">AIプロバイダー</p>
              <div className="grid grid-cols-3 gap-2">
                {(['openai', 'gemini', 'anthropic'] as AIProvider[]).map(p => (
                  <button
                    key={p}
                    onClick={() => { setAiProvider(p); setAiModel(''); }}
                    className="rounded-2xl py-2 px-1 text-center transition-all"
                    style={{
                      background: aiProvider === p ? '#D7FFB8' : '#F7F7F7',
                      border: `2px solid ${aiProvider === p ? '#58CC02' : '#e5e5e5'}`,
                      boxShadow: aiProvider === p ? '0 2px 0 #46A302' : 'none',
                    }}
                  >
                    <p className="font-extrabold text-xs leading-tight" style={{ color: aiProvider === p ? '#2d7a00' : '#4b4b4b' }}>
                      {p === 'openai' ? 'OpenAI' : p === 'gemini' ? 'Gemini' : 'Claude'}
                    </p>
                    <p className="text-[9px] font-bold leading-none mt-0.5" style={{ color: '#9e9e9e' }}>
                      {p === 'openai' ? 'ChatGPT' : p === 'gemini' ? 'Google' : 'Anthropic'}
                    </p>
                  </button>
                ))}
              </div>
            </div>

            {/* モデル（省略可） */}
            <div>
              <p className="font-extrabold text-duo-dark text-sm mb-1">
                モデル
                <span className="text-duo-gray font-bold text-xs ml-2">
                  省略時: {DEFAULT_MODELS[aiProvider]}
                </span>
              </p>
              <input
                type="text"
                value={aiModel}
                onChange={e => setAiModel(e.target.value)}
                placeholder={DEFAULT_MODELS[aiProvider]}
                className="w-full rounded-xl border-2 border-gray-200 px-3 py-2 text-sm font-bold text-duo-dark focus:outline-none focus:border-duo-green"
              />
            </div>

            {/* API キー */}
            <div>
              <p className="font-extrabold text-duo-dark text-sm mb-1">API キー</p>
              <div className="relative">
                <input
                  type={aiKeyVisible ? 'text' : 'password'}
                  value={aiApiKey}
                  onChange={e => setAiApiKey(e.target.value)}
                  placeholder={`${PROVIDER_LABELS[aiProvider]} の API キーを入力`}
                  className="w-full rounded-xl border-2 border-gray-200 px-3 py-2 pr-10 text-sm font-bold text-duo-dark focus:outline-none focus:border-duo-green"
                />
                <button
                  type="button"
                  onClick={() => setAiKeyVisible(v => !v)}
                  className="absolute right-3 top-1/2 -translate-y-1/2 text-duo-gray text-sm"
                >
                  {aiKeyVisible ? '🙈' : '👁'}
                </button>
              </div>
              <div
                className="mt-2 rounded-xl px-3 py-2 flex items-start gap-2"
                style={{ background: '#FFF8E1', border: '1px solid #FFD900' }}
              >
                <span className="text-xs mt-0.5">🔒</span>
                <p className="text-xs font-bold" style={{ color: '#7a5800' }}>
                  APIキーはこのデバイスにのみ保存され、外部サーバーには送信されません。
                </p>
              </div>
            </div>

            {/* 保存・クリア */}
            <div className="flex gap-2 pt-1">
              {aiApiKey && (
                <button
                  onClick={handleAiClear}
                  className="duo-btn-secondary flex-none px-4 py-2.5 text-sm"
                >
                  🗑 削除
                </button>
              )}
              <button
                onClick={handleAiSave}
                disabled={!aiApiKey.trim()}
                className="duo-btn-primary flex-1 py-2.5 text-sm"
                style={{ opacity: aiApiKey.trim() ? 1 : 0.5 }}
              >
                {aiSaved ? '✓ 保存しました！' : '🤖 AI設定を保存'}
              </button>
            </div>
          </div>
        </div>

        {/* ── 保存ボタン ──────────────────────────────────── */}
        <button
          onClick={handleSave}
          className="duo-btn-primary w-full text-lg py-4"
        >
          {saved ? '✓ 保存しました！' : '設定を保存'}
        </button>

      </div>
    </div>
  );
};
