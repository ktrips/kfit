import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

/// 週間レポート共有カード（docs/SamBezThieMuskJobs_plan.md P1「続いた実績の可視化」）
///
/// 今週の実績（ストリーク・セット数・XP）を 1 枚のカード画像にして SNS へ共有する。
/// 共有時に shared-reports/{shareId} へ公開データを書き込み、
/// カードには https://fit.ktrips.net/r/{shareId} を添付 — アプリ未インストールの人も
/// Web でカードを閲覧できる（アプリの外に出る最初のバイラル面）。
struct WeeklyReportView: View {
    @EnvironmentObject var authManager: AuthenticationManager

    @State private var weekSets = 0
    @State private var weekXP = 0
    @State private var aiComment: String? = nil
    @State private var loading = true
    @State private var sharing = false
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false
    @State private var errorMessage: String? = nil

    private var streak: Int { authManager.userProfile?.streak ?? 0 }
    private var username: String { authManager.userProfile?.username ?? "Fitingo User" }

    private static let weekLabelFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M/d"
        return f
    }()

    private var weekLabel: String {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
        let end = cal.date(byAdding: .day, value: 6, to: start) ?? Date()
        return "\(Self.weekLabelFmt.string(from: start))〜\(Self.weekLabelFmt.string(from: end))"
    }

    var body: some View {
        ZStack {
            Color.duoBg.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    if loading {
                        ProgressView().padding(.top, 60)
                    } else {
                        cardView
                            .padding(.top, 8)

                        Button {
                            Task { await share() }
                        } label: {
                            HStack(spacing: 8) {
                                if sharing {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: "square.and.arrow.up")
                                }
                                Text("カードをシェアする")
                                    .font(.system(size: 16, weight: .black))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Color.duoGreen))
                        }
                        .buttonStyle(.plain)
                        .disabled(sharing)

                        Text("シェアすると閲覧用リンク（fit.ktrips.net）が発行されます。\nカードに含まれるのは名前・連続日数・セット数だけです。")
                            .font(.caption2)
                            .foregroundColor(.duoSubtitle)
                            .multilineTextAlignment(.center)

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.duoRed)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("今週の実績をシェア")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadStats() }
        .sheet(isPresented: $showShareSheet) {
            SystemShareSheet(items: shareItems)
        }
    }

    private var cardView: some View {
        WeeklyReportCard(
            username: username,
            streak: streak,
            weekSets: weekSets,
            weekXP: weekXP,
            weekLabel: weekLabel,
            aiComment: aiComment
        )
        .frame(maxWidth: 340)
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - データ取得

    private func loadStats() async {
        guard let userId = Auth.auth().currentUser?.uid else { loading = false; return }
        let cal = Calendar.current
        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
        let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) ?? Date()

        let snap = try? await Firestore.firestore()
            .collection("users").document(userId)
            .collection("completed-sets")
            .whereField("timestamp", isGreaterThanOrEqualTo: weekStart)
            .whereField("timestamp", isLessThan: weekEnd)
            .getDocuments()

        weekSets = snap?.documents.count ?? 0
        weekXP = snap?.documents.reduce(0) { $0 + (($1.data()["totalXP"] as? Int) ?? 0) } ?? 0
        loading = false

        // AI コーチングコメントを非同期で取得（失敗してもカードは表示する）
        await fetchAIComment()
    }

    private func fetchAIComment() async {
        let fn = Functions.functions(region: "us-central1")
        var params: [String: Any] = [
            "streak": streak,
            "weekSets": weekSets,
            "weekXP": weekXP,
            "weekLabel": weekLabel,
        ]
        // HRV があれば渡す
        if let mgr = (UIApplication.shared.connectedScenes.first?.delegate as? NSObject)
            .flatMap({ _ in nil as HealthKitManager? }) {
            // HealthKitManager への参照は EnvironmentObject 経由でも取れるが、
            // ここでは直近の HRV 値があれば渡す（任意）
        }
        do {
            let result = try await fn.httpsCallable("generateWeeklyReport").call(params)
            if let data = result.data as? [String: Any],
               let comment = data["comment"] as? String,
               !comment.isEmpty {
                await MainActor.run { aiComment = comment }
            }
        } catch {
            // コメント取得失敗は無視（カードはコメントなしで表示）
            print("[WeeklyReport] AI comment fetch failed:", error.localizedDescription)
        }
    }

    // MARK: - 共有

    @MainActor
    private func share() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        sharing = true
        errorMessage = nil
        defer { sharing = false }

        // 1. 公開閲覧用ドキュメントを発行（ID は推測不能なランダム値）
        let shareId = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).lowercased()
        var data: [String: Any] = [
            "username": username,
            "streak": streak,
            "weekSets": weekSets,
            "weekXP": weekXP,
            "weekLabel": weekLabel,
            "authorUid": userId,
            "createdAt": FieldValue.serverTimestamp()
        ]
        if let comment = aiComment { data["aiComment"] = comment }
        do {
            try await Firestore.firestore()
                .collection("shared-reports").document(String(shareId)).setData(data)
        } catch {
            errorMessage = "リンクの発行に失敗しました。通信環境をご確認ください。"
            return
        }
        let urlString = "https://fit.ktrips.net/r/\(shareId)"

        // 2. カードを画像化（Instagram等の画像共有向け）
        let renderer = ImageRenderer(content:
            WeeklyReportCard(
                username: username,
                streak: streak,
                weekSets: weekSets,
                weekXP: weekXP,
                weekLabel: weekLabel,
                aiComment: aiComment
            )
            .frame(width: 360, height: 360)
        )
        renderer.scale = 3.0

        var items: [Any] = []
        if let image = renderer.uiImage { items.append(image) }
        if let url = URL(string: urlString) { items.append(url) }
        shareItems = items
        showShareSheet = true
    }
}

// MARK: - カード本体（画像レンダリングにも使用）

struct WeeklyReportCard: View {
    let username: String
    let streak: Int
    let weekSets: Int
    let weekXP: Int
    let weekLabel: String
    var aiComment: String? = nil

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.duoGreen, Color(red: 0.04, green: 0.52, blue: 0.35)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            VStack(spacing: 14) {
                HStack {
                    Text("Fitingo")
                        .font(.system(size: 17, weight: .black))
                        .foregroundColor(.white.opacity(0.9))
                    Spacer()
                    Text(weekLabel)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white.opacity(0.75))
                }

                Spacer()

                Text("🔥")
                    .font(.system(size: 52))
                Text("\(streak)日連続")
                    .font(.system(size: 40, weight: .black))
                    .foregroundColor(.white)

                HStack(spacing: 24) {
                    VStack(spacing: 2) {
                        Text("\(weekSets)")
                            .font(.system(size: 26, weight: .black))
                            .foregroundColor(.white)
                        Text("今週のセット")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    VStack(spacing: 2) {
                        Text("\(weekXP)")
                            .font(.system(size: 26, weight: .black))
                            .foregroundColor(.white)
                        Text("XP")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }

                Spacer()

                VStack(spacing: 4) {
                    // AI コーチングコメント
                    if let comment = aiComment, !comment.isEmpty {
                        Text(comment)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .padding(.horizontal, 4)
                            .padding(.bottom, 2)
                    }
                    Text("\(username) の今週の記録")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    Text("今度こそ、続く。 — fit.ktrips.net")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.75))
                }
            }
            .padding(24)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
