import React from 'react';
import { BOOKS, BookId } from './BookViewer';

interface BooksLandingProps {
  onSelectBook: (id: BookId) => void;
  onBackToApp?: () => void;
}

export const BooksLanding: React.FC<BooksLandingProps> = ({ onSelectBook, onBackToApp }) => {
  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-50 via-white to-green-50">
      {/* ── ヘッダー ── */}
      <header className="sticky top-0 z-50 bg-white/80 border-b border-gray-200 shadow-sm"
        style={{ backdropFilter: 'blur(12px)' }}>
        <div className="max-w-4xl mx-auto px-4 py-3 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <span className="text-2xl">📚</span>
            <div>
              <p className="text-xs text-gray-400 font-medium">fit.ktrips.net</p>
              <p className="text-sm font-black text-gray-800 leading-none">Books</p>
            </div>
          </div>
          {onBackToApp && (
            <button
              onClick={onBackToApp}
              className="text-sm text-green-600 hover:text-green-800 font-semibold border border-green-300 px-3 py-1.5 rounded-full transition-colors hover:bg-green-50"
            >
              ← アプリへ戻る
            </button>
          )}
        </div>
      </header>

      {/* ── ヒーロー ── */}
      <section className="max-w-4xl mx-auto px-4 pt-16 pb-10 text-center">
        <div className="inline-flex items-center gap-2 bg-green-100 text-green-700 px-4 py-1.5 rounded-full text-sm font-bold mb-6">
          <span>🇯🇵</span> 日本語電子書籍
        </div>
        <h1 className="text-4xl sm:text-5xl font-black text-gray-900 mb-4 leading-tight">
          Kenichi Yoshida の<br className="sm:hidden" />技術書コレクション
        </h1>
        <p className="text-gray-500 text-lg max-w-xl mx-auto">
          Apple Watchフィットネス・iOS個人開発の実践知識を凝縮。<br />
          Webで無料で読めます。
        </p>
      </section>

      {/* ── 書籍カード ── */}
      <section className="max-w-4xl mx-auto px-4 pb-20">
        <div className="grid sm:grid-cols-2 gap-6">
          {BOOKS.map((book) => (
            <button
              key={book.id}
              onClick={() => onSelectBook(book.id)}
              className={`
                group text-left rounded-2xl border-2 ${book.borderColor} ${book.bgColor}
                p-6 shadow-sm hover:shadow-lg transition-all duration-200
                hover:-translate-y-1 focus:outline-none focus:ring-4 focus:ring-offset-2
              `}
            >
              {/* 絵文字アイコン */}
              <div className="text-5xl mb-4">{book.emoji}</div>

              {/* タイトル */}
              <h2 className={`text-xl font-black ${book.color} leading-snug mb-1`}>
                {book.title}
              </h2>
              <p className="text-sm text-gray-500 mb-3 font-medium">{book.subtitle}</p>

              {/* 説明 */}
              <p className="text-sm text-gray-600 leading-relaxed mb-4">{book.description}</p>

              {/* タグ */}
              <div className="flex flex-wrap gap-1.5 mb-4">
                {book.tags.map((tag) => (
                  <span
                    key={tag}
                    className="text-xs bg-white/70 text-gray-600 border border-gray-200 px-2 py-0.5 rounded-full font-medium"
                  >
                    {tag}
                  </span>
                ))}
              </div>

              {/* CTA */}
              <div className={`flex items-center gap-2 ${book.color} font-bold text-sm group-hover:gap-3 transition-all`}>
                <span>今すぐ読む</span>
                <span>→</span>
              </div>
            </button>
          ))}
        </div>

        {/* ── Fitingo アプリ CTA ── */}
        <div className="mt-12 rounded-2xl bg-gradient-to-r from-green-500 to-emerald-600 text-white p-8 text-center shadow-xl">
          <div className="text-4xl mb-3">📱</div>
          <h3 className="text-2xl font-black mb-2">Fitingo アプリを試してみる</h3>
          <p className="text-green-100 mb-6 max-w-md mx-auto">
            本書で解説したフィットネス習慣化アプリが App Store で公開中。<br />
            Apple Watch Ultra 2 と連携してダイエットを記録しよう。
          </p>
          <div className="flex flex-col sm:flex-row gap-3 justify-center items-center">
            <a
              href="https://fit.ktrips.net"
              className="bg-white text-green-700 font-bold px-6 py-3 rounded-xl hover:bg-green-50 transition-colors"
            >
              🌐 Webアプリを使う
            </a>
            <a
              href="https://apps.apple.com/app/fitingo/id000000000"
              target="_blank"
              rel="noopener noreferrer"
              className="bg-black text-white font-bold px-6 py-3 rounded-xl hover:bg-gray-900 transition-colors flex items-center gap-2"
            >
              <svg className="w-5 h-5" viewBox="0 0 24 24" fill="currentColor">
                <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z"/>
              </svg>
              App Store
            </a>
          </div>
        </div>
      </section>

      {/* ── フッター ── */}
      <footer className="border-t border-gray-100 py-8 text-center text-gray-400 text-xs">
        <p>© 2026 吉田 顕一（Ken Yoshida）· <a href="https://fit.ktrips.net" className="hover:underline">fit.ktrips.net</a></p>
      </footer>
    </div>
  );
};
