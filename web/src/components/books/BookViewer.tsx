import React, { useEffect, useState, useCallback } from 'react';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';

// GitHub raw コンテンツのベース URL（画像パス変換に使用）
const GITHUB_RAW = 'https://raw.githubusercontent.com/ktrips/kfit/main/docs';

export type BookId = 'apple-watch-diet' | 'cursor-claude-code';

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
];

// 相対パスの画像を GitHub raw URL に変換
function resolveImageSrc(src: string): string {
  if (!src) return src;
  if (src.startsWith('http://') || src.startsWith('https://') || src.startsWith('/')) return src;
  // docs/ 以下の相対パスとして解決
  return `${GITHUB_RAW}/${src}`;
}

interface BookViewerProps {
  bookId: BookId;
  onBack: () => void;
}

export const BookViewer: React.FC<BookViewerProps> = ({ bookId, onBack }) => {
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
        <div className="max-w-3xl mx-auto px-4 py-3 flex items-center gap-3">
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
      <main className="max-w-3xl mx-auto px-4 py-8">
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
        {!loading && !error && (
          <ReactMarkdown
            remarkPlugins={[remarkGfm]}
            components={{
              // 画像: 相対パスを GitHub raw URL に変換、レスポンシブ
              img({ src, alt }) {
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
                return <h1 className="text-3xl font-black text-gray-900 mt-10 mb-4 leading-tight">{children}</h1>;
              },
              h2({ children }) {
                return <h2 className="text-2xl font-black text-gray-800 mt-8 mb-3 pt-4 border-t-2 border-green-200">{children}</h2>;
              },
              h3({ children }) {
                const id = String(children)
                  .toLowerCase()
                  .replace(/[^\w\u3040-\u30FF\u4E00-\u9FAF]+/g, '-')
                  .replace(/^-|-$/g, '');
                return <h3 id={id} className="text-xl font-bold text-gray-800 mt-6 mb-2">{children}</h3>;
              },
              h4({ children }) {
                return <h4 className="text-base font-bold text-green-700 mt-4 mb-1">{children}</h4>;
              },
              // 段落
              p({ children }) {
                return <p className="text-gray-700 leading-relaxed mb-4">{children}</p>;
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
                  return <code className="bg-gray-100 text-red-600 px-1.5 py-0.5 rounded text-sm font-mono">{children}</code>;
                }
                return (
                  <pre className="bg-gray-900 text-green-300 rounded-xl p-4 overflow-x-auto my-4 text-sm font-mono leading-relaxed">
                    <code>{children}</code>
                  </pre>
                );
              },
              // リスト
              ul({ children }) {
                return <ul className="list-disc list-inside space-y-1 mb-4 text-gray-700">{children}</ul>;
              },
              ol({ children }) {
                return <ol className="list-decimal list-inside space-y-1 mb-4 text-gray-700">{children}</ol>;
              },
              li({ children }) {
                return <li className="leading-relaxed">{children}</li>;
              },
              // テーブル
              table({ children }) {
                return (
                  <div className="overflow-x-auto my-6">
                    <table className="min-w-full text-sm border-collapse">{children}</table>
                  </div>
                );
              },
              th({ children }) {
                return <th className="bg-gray-100 border border-gray-300 px-3 py-2 text-left font-bold text-gray-700">{children}</th>;
              },
              td({ children }) {
                return <td className="border border-gray-200 px-3 py-2 text-gray-700">{children}</td>;
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
            }}
          >
            {content}
          </ReactMarkdown>
        )}
      </main>

      {/* ── フッター ── */}
      <footer className="max-w-3xl mx-auto px-4 py-12 text-center text-gray-400 text-xs">
        <p>© 2026 吉田 顕一 · <a href="https://fit.ktrips.net" className="hover:underline">fit.ktrips.net</a></p>
      </footer>
    </div>
  );
};
