import React from 'react';
import { BOOKS, BookId } from './BookViewer';

// App Store のリンク
const APP_STORE_URL = 'https://apps.apple.com/jp/app/kfit-fitingo/id6746108484';
interface BooksLandingProps {
  onSelectBook: (id: BookId) => void;
  onBackToApp?: () => void;
  isPlus?: boolean;
  isLoggedIn?: boolean;
}

export const BooksLanding: React.FC<BooksLandingProps> = ({
  onSelectBook,
  onBackToApp,
  isPlus = false,
  isLoggedIn = false,
}) => {
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
      <section className="max-w-2xl mx-auto px-4 pt-8 sm:pt-14 pb-6 sm:pb-10 text-center">
        <div className="inline-flex items-center gap-2 bg-green-100 text-green-700 px-4 py-1.5 rounded-full text-sm font-bold mb-5">
          <span>🇯🇵</span> 日本語電子書籍
        </div>
        <h1 className="text-3xl sm:text-4xl font-black text-gray-900 mb-3 leading-tight">
          Kenichi Yoshida の技術書コレクション
        </h1>
        <p className="text-gray-500 text-base sm:text-lg max-w-xl mx-auto">
          Apple Watchフィットネス・iOS個人開発の実践知識を凝縮。<br />
          {isPlus
            ? '全文をWebで読めます。'
            : 'ウェブで試し読みできます。全文はFitingo Plusで。'}
        </p>

        {/* Plusバナー（非Plusかつ未ログイン時） */}
        {!isPlus && !isLoggedIn && (
          <div className="mt-4 inline-flex items-center gap-2 bg-amber-50 border border-amber-200 text-amber-700 px-4 py-2 rounded-xl text-sm font-semibold">
            <span>⊕</span>
            <span>Fitingo Plusに登録すると全文をWebで読めます</span>
          </div>
        )}
        {!isPlus && isLoggedIn && (
          <div className="mt-4 inline-flex items-center gap-2 bg-amber-50 border border-amber-200 text-amber-700 px-4 py-2 rounded-xl text-sm font-semibold">
            <span>⊕</span>
            <span>Plusにアップグレードすると全文読めます</span>
            {onBackToApp && (
              <button
                onClick={onBackToApp}
                className="ml-2 underline hover:text-amber-900 text-xs"
              >
                アップグレード →
              </button>
            )}
          </div>
        )}
      </section>

      {/* ── 書籍カード ── */}
      <section className="max-w-2xl mx-auto px-4 pb-20">
        <div className="grid sm:grid-cols-2 gap-5">
          {BOOKS.filter((b) => !b.companionFor).map((book) => {
            // この書籍の続編・コンパニオン本を取得
            const companions = BOOKS.filter((b) => b.companionFor === book.id);
            return (
              <div key={book.id} className="flex flex-col gap-2">
                <button
                  onClick={() => onSelectBook(book.id)}
                  className={`
                    group text-left rounded-2xl border-2 ${book.borderColor} ${book.bgColor}
                    p-4 shadow-sm hover:shadow-lg transition-all duration-200
                    hover:-translate-y-1 focus:outline-none focus:ring-4 focus:ring-offset-2
                  `}
                >
                  {/* 絵文字アイコン */}
                  <div className="text-4xl mb-2">{book.emoji}</div>

                  {/* タイトル */}
                  <h2 className={`text-base font-black ${book.color} leading-snug mb-0.5`}>
                    {book.title}
                  </h2>
                  <p className="text-xs text-gray-500 mb-2 font-medium">{book.subtitle}</p>

                  {/* 説明 */}
                  <p className="text-xs text-gray-600 leading-relaxed mb-2">{book.description}</p>

                  {/* タグ */}
                  <div className="flex flex-wrap gap-1 mb-3">
                    {book.tags.slice(0, 4).map((tag) => (
                      <span
                        key={tag}
                        className="text-[11px] bg-white/70 text-gray-500 border border-gray-200 px-1.5 py-0.5 rounded-full"
                      >
                        {tag}
                      </span>
                    ))}
                  </div>

                  {/* CTA ラベル */}
                  <div className={`flex items-center gap-1 ${book.color} font-bold text-xs group-hover:gap-2 transition-all`}>
                    {isPlus ? (
                      <>
                        <span>全文をウェブで読む</span>
                        <span>→</span>
                      </>
                    ) : (
                      <>
                        <span>ウェブで試し読み</span>
                        <span>→</span>
                      </>
                    )}
                  </div>
                </button>

                {/* 続編・コンパニオン本リンク（全ユーザーに表示） */}
                {companions.map((companion) => (
                  <button
                    key={companion.id}
                    onClick={() => onSelectBook(companion.id)}
                    className={`
                      group text-left w-full rounded-2xl border-2 p-5 shadow-sm
                      transition-all duration-200 hover:-translate-y-1 focus:outline-none
                      focus:ring-2 focus:ring-offset-2
                      ${isPlus
                        ? 'border-purple-300 bg-gradient-to-br from-purple-50 to-violet-50 hover:shadow-lg focus:ring-purple-300'
                        : 'border-purple-200 bg-gradient-to-br from-purple-50/90 to-violet-50/90 hover:shadow-md focus:ring-purple-200'}
                    `}
                  >
                    {/* 上段: 絵文字 + Plusバッジ */}
                    <div className="flex items-center gap-2 mb-3">
                      <span className={`text-3xl ${!isPlus ? 'opacity-70' : ''}`}>{companion.emoji}</span>
                      <span className={`text-[11px] font-black text-white px-2 py-0.5 rounded-full leading-none ${isPlus ? 'bg-amber-500' : 'bg-purple-400'}`}>
                        ⊕ Plus限定
                      </span>
                    </div>
                    {/* タイトル */}
                    <p className={`text-base font-black leading-snug mb-1 ${isPlus ? 'text-purple-700' : 'text-purple-600'}`}>
                      {companion.title}
                    </p>
                    {/* サブタイトル */}
                    <p className="text-sm text-gray-500 mb-3 leading-relaxed">{companion.subtitle}</p>
                    {/* CTA */}
                    <div className={`flex items-center gap-1 font-bold text-sm group-hover:gap-2 transition-all ${isPlus ? 'text-purple-600' : 'text-purple-400'}`}>
                      {isPlus ? (
                        <><span>全文をウェブで読む</span><span>→</span></>
                      ) : (
                        <><span>ウェブで試し読み</span><span>→</span></>
                      )}
                    </div>
                  </button>
                ))}
              </div>
            );
          })}
        </div>

        {/* ── iOS アプリを使う CTA ── */}
        <div className="mt-6 rounded-2xl bg-gradient-to-r from-green-500 to-emerald-600 text-white p-4 text-center shadow-lg flex flex-col sm:flex-row items-center gap-3 justify-between">
          <div className="flex items-center gap-3 text-left">
            <span className="text-2xl">📱</span>
            <div>
              <p className="font-bold text-sm leading-tight">Fitingo iOSアプリ</p>
              <p className="text-green-100 text-xs">本書で解説したアプリを App Store で入手</p>
            </div>
          </div>
          <a
            href={APP_STORE_URL}
            target="_blank"
            rel="noopener noreferrer"
            className="shrink-0 bg-white text-green-700 font-bold px-5 py-2 rounded-xl hover:bg-green-50 transition-colors text-sm"
          >
            App Store でダウンロード
          </a>
        </div>
      </section>

      {/* ── フッター ── */}
      <footer className="border-t border-gray-100 py-8 text-center text-gray-400 text-xs">
        <p>© 2026 吉田 顕一（Ken Yoshida）· <a href="https://fit.ktrips.net" className="hover:underline">fit.ktrips.net</a></p>
      </footer>
    </div>
  );
};
