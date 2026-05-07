import type { BuilderChallenge } from '../types/challenge';

export const BUILDER_CHALLENGES: BuilderChallenge[] = [
  // ── EASY ──────────────────────────────────────────────────────────────────
  {
    id: 'counter-app',
    title: 'カウンターアプリ',
    difficulty: 'easy',
    difficultyStars: 1,
    description: 'シンプルなカウンターアプリをReactで作成します。',
    requirements: [
      'カウント表示（初期値0）',
      '+1 / -1 / リセットボタン',
      'カウントが0以下にならない制御',
      'Tailwind CSSでスタイリング',
    ],
    techStack: ['React', 'TypeScript', 'Tailwind CSS'],
    estimatedSessions: 1,
    baseTokenBudget: 2000,
    sessionBreakdown: [
      {
        session: 1,
        goal: '1セッションで完成',
        deliverables: ['Reactコンポーネント一式', 'スタイリング完了'],
      },
    ],
  },
  {
    id: 'janken-game',
    title: 'じゃんけんゲーム',
    difficulty: 'easy',
    difficultyStars: 1,
    description: 'コンピューターとじゃんけんをするゲームを作ります。',
    requirements: [
      'グー・チョキ・パーの選択ボタン',
      'コンピューターのランダム選択',
      '勝敗判定と結果表示',
      '戦績カウント（勝/負/引き分け）',
    ],
    techStack: ['React', 'TypeScript', 'Tailwind CSS'],
    estimatedSessions: 1,
    baseTokenBudget: 2500,
    sessionBreakdown: [
      {
        session: 1,
        goal: '1セッションで完成',
        deliverables: ['ゲームロジック', 'UI完成'],
      },
    ],
  },
  {
    id: 'bmi-calculator',
    title: 'BMI計算機',
    difficulty: 'easy',
    difficultyStars: 1,
    description: '身長・体重を入力してBMIを計算するアプリを作ります。',
    requirements: [
      '身長・体重の入力フォーム',
      'BMI計算と結果表示',
      'BMI分類の色分け表示（低体重/普通/肥満）',
      '入力バリデーション',
    ],
    techStack: ['React', 'TypeScript', 'Tailwind CSS'],
    estimatedSessions: 1,
    baseTokenBudget: 1800,
    sessionBreakdown: [
      { session: 1, goal: '1セッションで完成', deliverables: ['計算ロジック', 'UI完成'] },
    ],
  },
  {
    id: 'stopwatch',
    title: 'ストップウォッチ',
    difficulty: 'easy',
    difficultyStars: 1,
    description: 'スタート・ストップ・リセット機能付きのストップウォッチ。',
    requirements: [
      'ミリ秒単位の時間表示（MM:SS.ms）',
      'スタート・ストップ・リセットボタン',
      'ラップ記録機能',
      'ラップ履歴の表示（最新5件）',
    ],
    techStack: ['React', 'TypeScript', 'Tailwind CSS'],
    estimatedSessions: 1,
    baseTokenBudget: 2200,
    sessionBreakdown: [
      { session: 1, goal: '1セッションで完成', deliverables: ['タイマーロジック', 'ラップ機能', 'UI完成'] },
    ],
  },

  // ── NORMAL ────────────────────────────────────────────────────────────────
  {
    id: 'todo-app',
    title: 'ToDoアプリ',
    difficulty: 'normal',
    difficultyStars: 2,
    description: 'CRUD操作とLocalStorage永続化付きのToDoアプリ。',
    requirements: [
      'タスクの追加・編集・削除',
      '完了チェックボックス',
      'フィルター（全て/未完了/完了）',
      'LocalStorageで永続化',
      '空状態のイラスト表示',
    ],
    techStack: ['React', 'TypeScript', 'Tailwind CSS'],
    estimatedSessions: 2,
    baseTokenBudget: 5000,
    sessionBreakdown: [
      { session: 1, goal: 'CRUD + 基本UI', deliverables: ['タスク一覧', '追加・削除機能', 'チェックボックス'] },
      { session: 2, goal: 'LocalStorage + 仕上げ', deliverables: ['永続化', 'フィルター', '空状態UI'] },
    ],
  },
  {
    id: 'quiz-game',
    title: 'クイズゲーム',
    difficulty: 'normal',
    difficultyStars: 2,
    description: '10問のプログラミングクイズゲーム。タイマーとスコア表示付き。',
    requirements: [
      '4択問題（プログラミング系10問）',
      '30秒タイマー（時間切れで不正解）',
      'スコア計算と結果画面',
      '正解/不正解のアニメーション',
      'ランキング5位までLocalStorage保存',
    ],
    techStack: ['React', 'TypeScript', 'Tailwind CSS'],
    estimatedSessions: 2,
    baseTokenBudget: 6000,
    sessionBreakdown: [
      { session: 1, goal: '問題表示 + タイマー', deliverables: ['問題データ', '4択UI', 'タイマーロジック'] },
      { session: 2, goal: 'スコア + ランキング', deliverables: ['採点ロジック', '結果画面', 'ランキング保存'] },
    ],
  },
  {
    id: 'pomodoro-timer',
    title: 'ポモドーロタイマー',
    difficulty: 'normal',
    difficultyStars: 2,
    description: 'ポモドーロ・テクニックを実践できるタイマーアプリ。',
    requirements: [
      '25分作業 / 5分休憩の自動切り替え',
      '4ポモドーロ後に長休憩（15分）',
      '通知音（Web Audio API）',
      '今日の完了ポモドーロ数の表示',
      'セッション数のカスタマイズ設定',
    ],
    techStack: ['React', 'TypeScript', 'Tailwind CSS', 'Web Audio API'],
    estimatedSessions: 2,
    baseTokenBudget: 5500,
    sessionBreakdown: [
      { session: 1, goal: 'タイマーロジック', deliverables: ['作業/休憩サイクル', '自動切り替え'] },
      { session: 2, goal: '通知 + 設定 + 統計', deliverables: ['音声通知', 'カスタマイズ', '今日の統計'] },
    ],
  },

  // ── HARD ─────────────────────────────────────────────────────────────────
  {
    id: 'realtime-chat',
    title: 'リアルタイムチャット',
    difficulty: 'hard',
    difficultyStars: 3,
    description: 'Firebase Firestoreを使ったリアルタイムチャットアプリ。',
    requirements: [
      'Google認証でログイン',
      'メッセージのリアルタイム送受信',
      '送信者名とアバター表示',
      '既読表示（自分/相手の吹き出し分け）',
      '画像添付（Firebase Storage）',
      'ルーム機能（複数チャンネル）',
    ],
    techStack: ['React', 'TypeScript', 'Firebase Auth', 'Firestore', 'Firebase Storage'],
    estimatedSessions: 3,
    baseTokenBudget: 12000,
    sessionBreakdown: [
      { session: 1, goal: '認証 + 基本送受信', deliverables: ['Google Auth', 'Firestoreリスナー', 'メッセージUI'] },
      { session: 2, goal: 'ルーム + 画像', deliverables: ['ルーム管理', 'Storage連携', 'プレビュー'] },
      { session: 3, goal: '仕上げ + 最適化', deliverables: ['既読機能', 'スクロール制御', 'レスポンシブ'] },
    ],
  },
  {
    id: 'household-ledger',
    title: '家計簿アプリ',
    difficulty: 'hard',
    difficultyStars: 3,
    description: '収支記録・カテゴリ管理・グラフ表示付きの家計簿アプリ。',
    requirements: [
      '収入・支出の記録（金額・カテゴリ・日付・メモ）',
      'カテゴリ別集計',
      '月別収支グラフ（Canvas/SVG）',
      'CSV/JSONエクスポート',
      'Firestoreでクラウド保存',
    ],
    techStack: ['React', 'TypeScript', 'Tailwind CSS', 'Firestore', 'Canvas API'],
    estimatedSessions: 3,
    baseTokenBudget: 14000,
    sessionBreakdown: [
      { session: 1, goal: 'データ設計 + 入力UI', deliverables: ['Firestoreスキーマ', '収支入力フォーム'] },
      { session: 2, goal: '集計 + グラフ', deliverables: ['カテゴリ集計ロジック', '棒グラフ/円グラフ'] },
      { session: 3, goal: 'エクスポート + 仕上げ', deliverables: ['CSV出力', 'レスポンシブ対応'] },
    ],
  },

  // ── EXPERT ────────────────────────────────────────────────────────────────
  {
    id: 'markdown-editor',
    title: 'Markdownエディタ',
    difficulty: 'expert',
    difficultyStars: 4,
    description: 'リアルタイムプレビュー付きのMarkdownエディタ。',
    requirements: [
      'テキスト入力とリアルタイムMarkdownレンダリング',
      'ツールバー（Bold/Italic/見出し/リスト/コード）',
      'コードブロックのシンタックスハイライト',
      'ファイル保存・読み込み（IndexedDB）',
      'エクスポート（HTML/Markdown）',
      'ダークモード対応',
      'スプリットビュー・プレビューのみ切り替え',
    ],
    techStack: ['React', 'TypeScript', 'marked.js', 'highlight.js', 'IndexedDB'],
    estimatedSessions: 4,
    baseTokenBudget: 20000,
    sessionBreakdown: [
      { session: 1, goal: 'エディタ + パーサー', deliverables: ['marked.js統合', 'リアルタイムプレビュー'] },
      { session: 2, goal: 'ツールバー + ハイライト', deliverables: ['ツールバー全ボタン', 'highlight.js'] },
      { session: 3, goal: '保存 + エクスポート', deliverables: ['IndexedDB連携', 'HTML/MDエクスポート'] },
      { session: 4, goal: 'ダークモード + 仕上げ', deliverables: ['テーマ切り替え', 'ショートカットキー'] },
    ],
  },

  // ── MASTER ────────────────────────────────────────────────────────────────
  {
    id: 'ai-chat-app',
    title: 'AIチャットアプリ',
    difficulty: 'master',
    difficultyStars: 5,
    description: 'Claude APIを統合した本格的なAIチャットアプリ。',
    requirements: [
      'Claude API (claude-3-5-haiku) とのストリーミング会話',
      '会話履歴の管理とコンテキスト制御',
      'システムプロンプトのカスタマイズ',
      'トークン使用量のリアルタイム表示',
      'コスト計算（入力/出力別単価）',
      '会話のエクスポート（JSON/テキスト）',
      'Firestoreで会話履歴を永続化',
    ],
    techStack: ['React', 'TypeScript', 'Anthropic SDK', 'Firestore', 'Firebase Auth'],
    estimatedSessions: 6,
    baseTokenBudget: 30000,
    sessionBreakdown: [
      { session: 1, goal: '設計 + 認証', deliverables: ['全体設計', 'Google Auth', 'Firestoreスキーマ'] },
      { session: 2, goal: 'Claude API連携', deliverables: ['ストリーミング実装', 'メッセージUI'] },
      { session: 3, goal: '会話管理', deliverables: ['履歴保存', 'コンテキスト制御', 'チャット一覧'] },
      { session: 4, goal: 'プロンプト管理', deliverables: ['システムプロンプトUI', 'テンプレート機能'] },
      { session: 5, goal: 'コスト + 統計', deliverables: ['トークン表示', 'コスト計算', 'グラフ'] },
      { session: 6, goal: 'エクスポート + 仕上げ', deliverables: ['エクスポート機能', 'ショートカット', 'PWA対応'] },
    ],
    unlockCondition: 'HARDを全てクリアすること',
  },
];

export const DIFFICULTY_LABELS: Record<string, string> = {
  easy:   'EASY',
  normal: 'NORMAL',
  hard:   'HARD',
  expert: 'EXPERT',
  master: 'MASTER',
};

export const DIFFICULTY_COLORS: Record<string, string> = {
  easy:   'text-emerald-600 bg-emerald-50 border-emerald-200',
  normal: 'text-blue-600 bg-blue-50 border-blue-200',
  hard:   'text-orange-600 bg-orange-50 border-orange-200',
  expert: 'text-purple-600 bg-purple-50 border-purple-200',
  master: 'text-red-600 bg-red-50 border-red-200',
};
