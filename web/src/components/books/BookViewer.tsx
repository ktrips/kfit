import React, { useEffect, useState, useCallback } from 'react';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import rehypeRaw from 'rehype-raw';

// GitHub raw コンテンツのベース URL（画像パス変換に使用）
const GITHUB_RAW = 'https://raw.githubusercontent.com/ktrips/kfit/main/docs';

// 無料で読める文字数（おおよそ10ページ分）
const FREE_CHAR_LIMIT = 8000;

// Kindle 販売リンク（本ごとに設定）
export const KINDLE_URLS: Record<BookId, string> = {
  'apple-watch-diet': 'https://amzn.to/4ek5fHi',
  'cursor-claude-code': 'https://amzn.to/4w8mPE2',
  'cursor-claude-code-plus': 'https://amzn.to/4ek5fHi',
};

export type BookId = 'apple-watch-diet' | 'cursor-claude-code' | 'cursor-claude-code-plus';

interface BookMeta {
  id: BookId;
  title: string;
  subtitle: string;
  emoji: string;
  color: string;        // Tailwind text color
  bgColor: string;      // Tailwind bg color
  borderColor: string;  // Tailwind border color
  description: string;
  tags: string[];
  companionFor?: BookId; // この本が「続編・関連書」である場合の親BookId
}

export const BOOKS: BookMeta[] = [
  {
    id: 'apple-watch-diet',
    title: 'AppleWatch Diet Ultra2',
    subtitle: 'アップルウォッチ・ダイエット Ultra2',
    emoji: '⌚',
    color: 'text-green-600',
    bgColor: 'bg-green-50',
    borderColor: 'border-green-400',
    description:
      'Apple Watch Ultra 2を使ったダイエット・健康管理の100メソッドを徹底解説。' +
      'Fitingoアプリとの連携で習慣化を加速。',
    tags: ['Apple Watch', 'ダイエット', 'フィットネス', '健康管理', 'Fitingo'],
  },
  {
    id: 'cursor-claude-code',
    title: 'Cursor + ClaudeでiPhoneアプリを作る',
    subtitle: '週末だけでiOS・Apple Watchアプリを作る方法',
    emoji: '📱',
    color: 'text-blue-600',
    bgColor: 'bg-blue-50',
    borderColor: 'border-blue-400',
    description:
      'CursorとClaude Sonnetを使ってSwiftUI・HealthKit・Apple Watch連携アプリを' +
      '個人開発した全工程を解説する実践書。',
    tags: ['Cursor', 'Claude', 'SwiftUI', 'iOS', 'Apple Watch', '個人開発'],
  },
  {
    id: 'cursor-claude-code-plus',
    title: 'iPhoneアプリ＋！マーケティングする方法',
    subtitle: '個人開発アプリにPlus機能で収益化！',
    emoji: '🚀',
    color: 'text-purple-600',
    bgColor: 'bg-purple-50',
    borderColor: 'border-purple-400',
    description:
      'アプリ開発の次のステップ。Kindleドキュメント作成・KDP出版・Freemium設計・' +
      'SNSマーケティングまで実践的に解説するPlusガイド。',
    tags: ['マーケティング', 'Kindle', 'Freemium', 'Plus', 'SNS', '収益化'],
    companionFor: 'cursor-claude-code',
  },
];

// 相対パスの画像を GitHub raw URL に変換
function resolveImageSrc(src: string): string {
  if (!src) return src;
  if (src.startsWith('http://') || src.startsWith('https://') || src.startsWith('/')) return src;
  // docs/ 以下の相対パスとして解決
  return `${GITHUB_RAW}/${src}`;
}

// App Store のリンク
const APP_STORE_URL = 'https://apps.apple.com/jp/app/kfit-fitingo/id6746108484';

interface BookViewerProps {
  bookId: BookId;
  onBack: () => void;
  isPlus?: boolean;
}

export const BookViewer: React.FC<BookViewerProps> = ({ bookId, onBack, isPlus = false }) => {
  const [content, setContent] = useState<string>('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [tocOpen, setTocOpen] = useState(false);

  const meta = BOOKS.find((b) => b.id === bookId);

  useEffect(() => {
    setLoading(true);
    setError(null);
    fetch(`/books/${bookId}.md`)
      .then((r) => {
        if (!r.ok) throw new Error(`${r.status} ${r.statusText}`);
        return r.text();
      })
      .then((text) => {
        setContent(text);
        setLoading(false);
      })
      .catch((e) => {
        setError(e.message);
        setLoading(false);
      });
  }, [bookId]);

  // URL を書き換え（戻るボタン対応）
  useEffect(() => {
    window.history.pushState({}, '', `/books/${bookId}`);
    return () => {
      // cleanup: handled by onBack
    };
  }, [bookId]);

  const handleBack = useCallback(() => {
    window.history.pushState({}, '', '/books');
    onBack();
  }, [onBack]);

  if (!meta) return null;

  return (
    <div className="min-h-screen bg-white">
      {/* ── 固定ヘッダー ── */}
      <header
        className="sticky top-0 z-50 bg-white border-b border-gray-200 shadow-sm"
        style={{ backdropFilter: 'blur(8px)' }}
      >
        <div className="max-w-2xl mx-auto px-4 py-3 flex items-center gap-3">
          <button
            onClick={handleBack}
            className="flex items-center gap-1 text-gray-500 hover:text-gray-800 transition-colors text-sm font-semibold"
          >
            ← 本の一覧
          </button>
          <div className="flex-1 min-w-0">
            <p className="text-xs text-gray-400 truncate">fit.ktrips.net/books</p>
            <p className="text-sm font-bold text-gray-800 truncate">{meta.title}</p>
          </div>
          <button
            onClick={() => setTocOpen((v) => !v)}
            className="text-xs bg-gray-100 hover:bg-gray-200 px-3 py-1.5 rounded-full font-semibold transition-colors"
          >
            目次
          </button>
        </div>
      </header>

      {/* ── TOC ドロワー ── */}
      {tocOpen && content && (
        <div className="fixed inset-0 z-40 flex" onClick={() => setTocOpen(false)}>
          <div className="absolute right-0 top-0 h-full w-72 bg-white shadow-2xl overflow-y-auto p-6"
            onClick={(e) => e.stopPropagation()}>
            <h3 className="font-black text-gray-800 mb-4 text-lg">目次</h3>
            <ul className="space-y-1">
              {content
                .split('\n')
                .filter((l) => l.startsWith('#'))
                .slice(0, 40)
                .map((line, i) => {
                  const level = (line.match(/^#+/) || [''])[0].length;
                  const text = line.replace(/^#+\s*/, '');
                  const anchor = text
                    .toLowerCase()
                    .replace(/[^\w\u3040-\u30FF\u4E00-\u9FAF]+/g, '-')
                    .replace(/^-|-$/g, '');
                  return (
                    <li key={i} style={{ paddingLeft: `${(level - 1) * 12}px` }}>
                      <a
                        href={`#${anchor}`}
                        className="text-sm text-blue-600 hover:underline block py-0.5"
                        onClick={() => setTocOpen(false)}
                      >
                        {text}
                      </a>
                    </li>
                  );
                })}
            </ul>
          </div>
        </div>
      )}

      {/* ── 本文 ── */}
      <main className="max-w-2xl mx-auto px-5 py-6 sm:py-8">
        {loading && (
          <div className="flex flex-col items-center justify-center py-32 gap-4">
            <div className="w-12 h-12 border-4 border-green-400 border-t-transparent rounded-full animate-spin" />
            <p className="text-gray-500 font-semibold">読み込み中…</p>
          </div>
        )}
        {error && (
          <div className="text-center py-20">
            <p className="text-red-500 font-bold text-lg mb-2">読み込みエラー</p>
            <p className="text-gray-400 text-sm">{error}</p>
          </div>
        )}
        {!loading && !error && (() => {
          // Plus ユーザーは全文表示、非Plusは試し読み分のみ
          const needsTruncation = !isPlus && content.length > FREE_CHAR_LIMIT;
          let displayContent = content;
          if (needsTruncation) {
            // FREE_CHAR_LIMIT 以降で最初の ## 見出しを切れ目にする
            const idx = content.indexOf('\n## ', FREE_CHAR_LIMIT);
            displayContent = idx !== -1 ? content.slice(0, idx) : content.slice(0, FREE_CHAR_LIMIT);
          }

          const mdComponents = {
              // 画像: 相対パスを GitHub raw URL に変換、レスポンシブ
              img({ src, alt }: { src?: string; alt?: string }) {
                const resolved = resolveImageSrc(src ?? '');
                return (
                  <figure className="my-6 text-center">
                    <img
                      src={resolved}
                      alt={alt ?? ''}
                      className="mx-auto rounded-xl shadow-md max-w-full"
                      style={{ maxHeight: '400px', objectFit: 'contain' }}
                      loading="lazy"
                    />
                    {alt && (
                      <figcaption className="text-xs text-gray-400 mt-2 italic">{alt}</figcaption>
                    )}
                  </figure>
                );
              },
              // 見出し
              h1({ children }) {
                return <h1 className="text-2xl sm:text-3xl font-black text-gray-900 mt-8 mb-3 leading-tight">{children}</h1>;
              },
              h2({ children }) {
                return <h2 className="text-xl sm:text-2xl font-black text-gray-800 mt-7 mb-3 pt-4 border-t-2 border-green-200">{children}</h2>;
              },
              h3({ children }) {
                const id = String(children)
                  .toLowerCase()
                  .replace(/[^\w\u3040-\u30FF\u4E00-\u9FAF]+/g, '-')
                  .replace(/^-|-$/g, '');
                return <h3 id={id} className="text-lg sm:text-xl font-bold text-gray-800 mt-5 mb-2">{children}</h3>;
              },
              h4({ children }) {
                return <h4 className="text-base font-bold text-green-700 mt-4 mb-1">{children}</h4>;
              },
              // 段落
              p({ children }) {
                return <p className="text-[15px] sm:text-base text-gray-700 leading-[1.85] mb-4">{children}</p>;
              },
              // 引用（ポイントボックス）
              blockquote({ children }) {
                return (
                  <blockquote className="border-l-4 border-amber-400 bg-amber-50 px-4 py-3 my-4 rounded-r-xl text-amber-900 text-sm font-medium">
                    {children}
                  </blockquote>
                );
              },
              // コードブロック
              code(props) {
                const { children, className } = props as { children?: React.ReactNode; className?: string };
                const isBlock = !!className;
                if (!isBlock) {
                  return <code className="bg-gray-100 text-red-600 px-1.5 py-0.5 rounded text-[13px] font-mono">{children}</code>;
                }
                return (
                  <pre className="bg-gray-900 text-green-300 rounded-xl p-4 overflow-x-auto my-4 text-xs sm:text-sm font-mono leading-relaxed">
                    <code>{children}</code>
                  </pre>
                );
              },
              // リスト
              ul({ children }) {
                return <ul className="list-disc list-outside pl-5 space-y-1.5 mb-4 text-gray-700 text-[15px] sm:text-base">{children}</ul>;
              },
              ol({ children }) {
                return <ol className="list-decimal list-outside pl-5 space-y-1.5 mb-4 text-gray-700 text-[15px] sm:text-base">{children}</ol>;
              },
              li({ children }) {
                return <li className="leading-relaxed pl-1">{children}</li>;
              },
              // テーブル
              table({ children }) {
                return (
                  <div className="overflow-x-auto my-5 -mx-1">
                    <table className="min-w-full text-xs sm:text-sm border-collapse">{children}</table>
                  </div>
                );
              },
              th({ children }) {
                return <th className="bg-gray-100 border border-gray-300 px-2 sm:px-3 py-2 text-left font-bold text-gray-700 whitespace-nowrap">{children}</th>;
              },
              td({ children }) {
                return <td className="border border-gray-200 px-2 sm:px-3 py-2 text-gray-700">{children}</td>;
              },
              // 水平線
              hr() {
                return <hr className="my-8 border-t-2 border-gray-100" />;
              },
              // リンク
              a({ href, children }) {
                return (
                  <a href={href} className="text-blue-600 hover:underline font-medium" target={href?.startsWith('http') ? '_blank' : undefined} rel="noopener noreferrer">
                    {children}
                  </a>
                );
              },
              // 太字
              strong({ children }) {
                return <strong className="font-bold text-gray-900">{children}</strong>;
              },
          };

          return (
            <>
              {/* ── 本文 ── */}
              <ReactMarkdown
                remarkPlugins={[remarkGfm]}
                rehypePlugins={[rehypeRaw]}
                components={mdComponents}
              >
                {displayContent}
              </ReactMarkdown>

              {/* ── ペイウォール（非Plusかつコンテンツが制限されている場合のみ） ── */}
              {needsTruncation && (
                <div className="mt-8">
                  {/* フェードアウト境界 */}
                  <div className="relative h-32 -mt-32 pointer-events-none"
                    style={{ background: 'linear-gradient(to bottom, transparent, white)' }} />

                  {/* ペイウォールカード */}
                  <div className="rounded-2xl border-2 border-green-300 bg-green-50 p-6 text-center shadow-lg">
                    <div className="text-4xl mb-3">⊕</div>
                    <h3 className="text-xl font-black text-gray-800 mb-2">
                      ここまでは試し読みできます
                    </h3>
                    <p className="text-base text-gray-700 mb-1 leading-relaxed font-semibold">
                      全文を読むには Fitingo Plus が必要です
                    </p>
                    <p className="text-sm text-gray-500 mb-5 leading-relaxed">
                      Fitingo Plus に登録すると、全書籍をWebで全文読むことができます。
                    </p>

                    <div className="flex flex-col sm:flex-row gap-3 justify-center items-center">
                      <a
                        href={APP_STORE_URL}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="inline-flex items-center gap-2 bg-green-500 hover:bg-green-600 text-white font-black px-6 py-3 rounded-xl text-base transition-colors shadow-md"
                      >
                        <svg viewBox="0 0 24 24" fill="currentColor" className="w-5 h-5">
                          <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11"/>
                        </svg>
                        iOSを開く → Plusに登録
                      </a>
                      <a
                        href="https://fit.ktrips.net"
                        className="inline-flex items-center gap-2 bg-white border-2 border-green-400 text-green-700 hover:bg-green-50 font-bold px-6 py-3 rounded-xl text-base transition-colors"
                      >
                        🌐 WebアプリでPlus登録
                      </a>
                    </div>
                  </div>
                </div>
              )}

              {/* ── Plus ユーザー向けフッター ── */}
              {isPlus && (
                <div className="mt-12 rounded-2xl bg-gradient-to-r from-green-50 to-emerald-50 border border-green-200 p-6 text-center">
                  <p className="text-green-700 font-bold text-sm mb-1">⊕ Fitingo Plus で全文公開中</p>
                  <p className="text-gray-500 text-xs">引き続きFitingoアプリで習慣を記録しましょう</p>
                  <a
                    href={APP_STORE_URL}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="mt-3 inline-flex items-center gap-1.5 bg-green-500 hover:bg-green-600 text-white font-bold px-4 py-2 rounded-lg text-sm transition-colors"
                  >
                    <svg viewBox="0 0 24 24" fill="currentColor" className="w-4 h-4">
                      <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11"/>
                    </svg>
                    iOSを開く
                  </a>
                </div>
              )}
            </>
          );
        })()}
      </main>

      {/* ── フッター ── */}
      <footer className="max-w-2xl mx-auto px-5 py-10 text-center text-gray-400 text-xs">
        <p>© 2026 吉田 顕一 · <a href="https://fit.ktrips.net" className="hover:underline">fit.ktrips.net</a></p>
      </footer>
    </div>
  );
};
