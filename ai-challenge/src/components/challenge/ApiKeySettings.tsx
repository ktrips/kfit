import { useState } from 'react';
import { Key, Eye, EyeOff, CheckCircle, ArrowLeft } from 'lucide-react';
import { useGameStore } from '../../store/gameStore';

export function ApiKeySettings() {
  const { apiKey, setApiKey, setView } = useGameStore();
  const [input, setInput] = useState(apiKey);
  const [showKey, setShowKey] = useState(false);
  const [saved, setSaved] = useState(false);

  const handleSave = () => {
    setApiKey(input.trim());
    setSaved(true);
    setTimeout(() => setSaved(false), 2000);
  };

  const isValid = input.trim().startsWith('sk-ant-');

  return (
    <div className="min-h-screen bg-gray-50">
      <div className="max-w-lg mx-auto px-4 py-10">
        <button
          onClick={() => setView('map')}
          className="flex items-center gap-1.5 text-gray-500 hover:text-brand mb-8 text-sm font-medium transition-colors"
        >
          <ArrowLeft className="w-4 h-4" />
          マップに戻る
        </button>

        <h1 className="text-2xl font-black text-gray-900 mb-2">設定</h1>
        <p className="text-gray-500 text-sm mb-8">
          チャレンジにはAnthropic APIキーが必要です。キーはブラウザのlocalStorageにのみ保存され、外部には送信されません。
        </p>

        <div className="bg-white rounded-2xl border border-gray-200 shadow-sm p-6">
          <div className="flex items-center gap-2 mb-4">
            <Key className="w-5 h-5 text-brand" />
            <h2 className="font-bold text-gray-900">Anthropic APIキー</h2>
          </div>

          <div className="relative mb-3">
            <input
              type={showKey ? 'text' : 'password'}
              value={input}
              onChange={(e) => setInput(e.target.value)}
              placeholder="sk-ant-api..."
              className="w-full border border-gray-300 rounded-xl px-4 py-3 pr-12 text-sm font-mono focus:outline-none focus:ring-2 focus:ring-brand focus:border-transparent"
            />
            <button
              type="button"
              onClick={() => setShowKey((v) => !v)}
              className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600"
            >
              {showKey ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
            </button>
          </div>

          {input && !isValid && (
            <p className="text-red-500 text-xs mb-3">
              APIキーは "sk-ant-" から始まる必要があります
            </p>
          )}

          <button
            onClick={handleSave}
            disabled={!isValid}
            className={`w-full py-3 rounded-xl font-bold text-sm transition-all ${
              saved
                ? 'bg-emerald-500 text-white'
                : isValid
                ? 'bg-brand text-white hover:bg-brand-dark'
                : 'bg-gray-100 text-gray-400 cursor-not-allowed'
            }`}
          >
            {saved ? (
              <span className="flex items-center justify-center gap-2">
                <CheckCircle className="w-4 h-4" /> 保存しました
              </span>
            ) : (
              '保存する'
            )}
          </button>
        </div>

        <div className="mt-6 bg-amber-50 border border-amber-200 rounded-xl p-4 text-sm text-amber-800">
          <p className="font-semibold mb-1">APIキーの取得方法</p>
          <ol className="list-decimal list-inside space-y-1 text-amber-700">
            <li>console.anthropic.com にアクセス</li>
            <li>「API Keys」→「Create Key」</li>
            <li>生成されたキーをコピーして貼り付け</li>
          </ol>
          <p className="mt-2 text-xs text-amber-600">
            ※ チャレンジで使用するモデルは claude-haiku-4-5（最小コスト）です
          </p>
        </div>
      </div>
    </div>
  );
}
