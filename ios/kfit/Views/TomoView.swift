import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - TomoManager

@MainActor
final class TomoManager: ObservableObject {

    struct TomoEntry: Identifiable {
        let id: String
        let email: String
        let username: String
        let totalPoints: Int
        let streak: Int
        var weeklyPoints: Int
        var isMe: Bool = false
        var rank: Int = 0
    }

    enum AddResult {
        case idle, searching
        case notFound(String)   // email → show share sheet
        case added(String)      // success → name
        case alreadyAdded
        case selfAdd
        case error(String)
    }

    @Published var entries: [TomoEntry] = []
    @Published var isLoading = false
    @Published var addResult: AddResult = .idle

    private let db = Firestore.firestore()

    func load() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        defer { isLoading = false }

        var all: [TomoEntry] = []

        // Self
        if let me = AuthenticationManager.shared.userProfile {
            let wPts = await weeklyPoints(userId: uid)
            all.append(TomoEntry(id: uid, email: me.email, username: me.username,
                                 totalPoints: me.totalPoints, streak: me.streak,
                                 weeklyPoints: wPts, isMe: true))
        }

        // Tomos
        let snap = try? await db.collection("users").document(uid)
            .collection("tomos").getDocuments()
        for doc in snap?.documents ?? [] {
            let tomoId = doc.documentID
            guard let profileDoc = try? await db.collection("users").document(tomoId).getDocument(),
                  profileDoc.exists,
                  let data = profileDoc.data() else { continue }
            let wPts = await weeklyPoints(userId: tomoId)
            all.append(TomoEntry(
                id: tomoId,
                email: data["email"] as? String ?? "",
                username: data["username"] as? String ?? "TOMO",
                totalPoints: data["totalPoints"] as? Int ?? 0,
                streak: data["streak"] as? Int ?? 0,
                weeklyPoints: wPts
            ))
        }

        all.sort { $0.weeklyPoints > $1.weeklyPoints }
        for i in all.indices { all[i].rank = i + 1 }
        entries = all
    }

    func addTomo(email rawEmail: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let email = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard email.contains("@") else {
            addResult = .error("有効なメールアドレスを入力してください")
            return
        }
        if entries.contains(where: { !$0.isMe && $0.email.lowercased() == email }) {
            addResult = .alreadyAdded; return
        }

        addResult = .searching
        let snap = try? await db.collection("users")
            .whereField("email", isEqualTo: email)
            .limit(to: 1)
            .getDocuments()
        guard let tomoDoc = snap?.documents.first else {
            addResult = .notFound(email); return
        }
        let tomoId = tomoDoc.documentID
        guard tomoId != uid else { addResult = .selfAdd; return }

        let now = Timestamp(date: Date())
        let myEmail = AuthenticationManager.shared.userProfile?.email ?? ""
        try? await db.collection("users").document(uid)
            .collection("tomos").document(tomoId)
            .setData(["email": email, "addedAt": now])
        try? await db.collection("users").document(tomoId)
            .collection("tomos").document(uid)
            .setData(["email": myEmail, "addedAt": now])

        let name = tomoDoc.data()["username"] as? String ?? email
        addResult = .added(name)
        await load()
    }

    func removeTomo(id: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try? await db.collection("users").document(uid)
            .collection("tomos").document(id).delete()
        entries.removeAll { $0.id == id }
        for i in entries.indices { entries[i].rank = i + 1 }
    }

    private func weeklyPoints(userId: String) async -> Int {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)  // 1=Sun, 2=Mon...
        let daysSinceMonday = weekday == 1 ? 6 : weekday - 2
        guard let monday = calendar.date(byAdding: .day, value: -daysSinceMonday,
                                         to: calendar.startOfDay(for: today)) else { return 0 }
        let snap = try? await db.collection("users").document(userId)
            .collection("completed-exercises")
            .whereField("timestamp", isGreaterThanOrEqualTo: Timestamp(date: monday))
            .getDocuments()
        return snap?.documents.compactMap { $0.data()["points"] as? Int }.reduce(0, +) ?? 0
    }
}

// MARK: - Share Sheet

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - TomoView

struct TomoView: View {
    @Binding var selectedTab: Int
    @Binding var showRecordMenu: Bool
    @StateObject private var manager = TomoManager()
    @State private var emailInput = ""
    @State private var showShareSheet = false
    @State private var shareText = ""
    @FocusState private var emailFocused: Bool

    var body: some View {
        NavigationView {
            ZStack {
                Color.duoBg.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        tomoHeader
                        inviteCard
                        rankingSection
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                }
                .refreshable { await manager.load() }
            }
            .navigationBarHidden(true)
        }
        .task { await manager.load() }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [shareText])
        }
    }

    // MARK: - Header

    private var tomoHeader: some View {
        ZStack {
            LinearGradient(
                colors: [Color.duoBlue, Color(red: 0.06, green: 0.56, blue: 0.85)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image("mascot")
                        .resizable().scaledToFill()
                        .frame(width: 18, height: 18)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 0.4))
                    HStack(spacing: 0) {
                        Text("Tomo")
                            .foregroundColor(Color(red: 1.0, green: 0.29, blue: 0.10))
                        Text("lingo")
                            .foregroundColor(.white)
                    }
                    .font(.system(size: 14, weight: .black, design: .rounded))
                }
                Spacer()
                let tomoCount = manager.entries.filter { !$0.isMe }.count
                HStack(spacing: 3) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))
                    Text("\(tomoCount)")
                        .font(.system(size: 12, weight: .black))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.2))
                .cornerRadius(10)

                HeaderNavigationMenu(selectedTab: $selectedTab, showRecordMenu: $showRecordMenu)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(height: 44)
        .cornerRadius(14)
        .shadow(color: Color.duoBlue.opacity(0.25), radius: 6, y: 3)
    }

    // MARK: - Invite Card

    private var inviteCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color.duoBlue)
                Text("TOMOを招待")
                    .font(.system(size: 13, weight: .black))
                    .foregroundColor(Color.duoDark)
            }

            HStack(spacing: 8) {
                TextField("Googleアカウントのメールアドレス", text: $emailInput)
                    .font(.system(size: 13))
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .focused($emailFocused)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.duoBg)
                    .cornerRadius(8)

                Button {
                    emailFocused = false
                    Task { await manager.addTomo(email: emailInput) }
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(emailInput.trimmingCharacters(in: .whitespaces).isEmpty
                            ? Color.duoBlue.opacity(0.3) : Color.duoBlue)
                }
                .buttonStyle(.plain)
                .disabled(emailInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            addResultView
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
    }

    @ViewBuilder
    private var addResultView: some View {
        switch manager.addResult {
        case .idle:
            EmptyView()
        case .searching:
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.75)
                Text("検索中...").font(.caption).foregroundColor(Color.duoSubtitle)
            }
        case .notFound(let email):
            VStack(alignment: .leading, spacing: 8) {
                Text("このメールアドレスのユーザーはまだFitingoに登録していません。招待を送りましょう！")
                    .font(.caption)
                    .foregroundColor(Color.duoSubtitle)
                Button {
                    shareText = "【Fitingo招待】\n\n\(email) さん、一緒にトレーニングしましょう！\n\nFitingoアプリをダウンロードしてTOMOになろう！\nhttps://apps.apple.com/app/fitingo"
                    showShareSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 11, weight: .bold))
                        Text("招待を送る")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Color.duoBlue)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        case .added(let name):
            Label("\(name) をTOMOに追加しました！", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundColor(Color.duoGreen)
        case .alreadyAdded:
            Label("すでにTOMOです", systemImage: "info.circle.fill")
                .font(.caption).foregroundColor(Color.duoOrange)
        case .selfAdd:
            Label("自分自身は追加できません", systemImage: "xmark.circle.fill")
                .font(.caption).foregroundColor(Color.duoRed)
        case .error(let msg):
            Label(msg, systemImage: "xmark.circle.fill")
                .font(.caption).foregroundColor(Color.duoRed)
        }
    }

    // MARK: - Ranking

    @ViewBuilder
    private var rankingSection: some View {
        if manager.isLoading && manager.entries.isEmpty {
            VStack(spacing: 10) {
                ProgressView()
                Text("読み込み中...").font(.caption).foregroundColor(Color.duoSubtitle)
            }
            .frame(maxWidth: .infinity)
            .padding(32)
            .background(Color.white)
            .cornerRadius(14)
            .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
        } else if manager.entries.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "person.2.slash")
                    .font(.system(size: 30))
                    .foregroundColor(Color.duoSubtitle)
                Text("まだTOMOがいません")
                    .font(.subheadline).fontWeight(.bold)
                    .foregroundColor(Color.duoSubtitle)
                Text("メールアドレスを入力してTOMOを追加しよう！")
                    .font(.caption).foregroundColor(Color.duoSubtitle)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(32)
            .background(Color.white)
            .cornerRadius(14)
            .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                rankingHeader
                ForEach(manager.entries) { entry in
                    rankRow(entry)
                    if entry.id != manager.entries.last?.id {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .background(Color.white)
            .cornerRadius(14)
            .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
        }
    }

    private var rankingHeader: some View {
        HStack(spacing: 0) {
            Text("順位")
                .font(.system(size: 10, weight: .black))
                .foregroundColor(Color.duoSubtitle)
                .frame(width: 44, alignment: .center)
            Text("名前")
                .font(.system(size: 10, weight: .black))
                .foregroundColor(Color.duoSubtitle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 8)
            Text("今週pt")
                .font(.system(size: 10, weight: .black))
                .foregroundColor(Color.duoBlue)
                .frame(width: 58, alignment: .trailing)
            Text("累計pt")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(Color.duoSubtitle)
                .frame(width: 52, alignment: .trailing)
            Text("連続")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(Color.duoSubtitle)
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.duoBg)
    }

    private func rankRow(_ entry: TomoManager.TomoEntry) -> some View {
        HStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(rankBadgeColor(entry.rank))
                    .frame(width: 28, height: 28)
                Text("\(entry.rank)")
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(.white)
            }
            .frame(width: 44)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(entry.username)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color.duoDark)
                        .lineLimit(1)
                    if entry.isMe {
                        Text("あなた")
                            .font(.system(size: 8, weight: .black))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.duoBlue)
                            .cornerRadius(4)
                    }
                }
                Text(entry.email)
                    .font(.system(size: 10))
                    .foregroundColor(Color.duoSubtitle)
                    .lineLimit(1)
            }
            .padding(.leading, 8)
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 0) {
                Text("\(entry.weeklyPoints)")
                    .font(.system(size: 14, weight: .black))
                    .foregroundColor(Color.duoBlue)
                Text("pt")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Color.duoSubtitle)
            }
            .frame(width: 58, alignment: .trailing)

            VStack(spacing: 0) {
                Text("\(entry.totalPoints)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color.duoDark)
                Text("pt")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(Color.duoSubtitle)
            }
            .frame(width: 52, alignment: .trailing)

            VStack(spacing: 0) {
                HStack(spacing: 1) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 8))
                        .foregroundColor(Color(hex: "#FF9600"))
                    Text("\(entry.streak)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color.duoDark)
                }
                Text("日")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(Color.duoSubtitle)
            }
            .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(entry.isMe ? Color.duoBlue.opacity(0.05) : Color.clear)
        .contextMenu {
            if !entry.isMe {
                Button(role: .destructive) {
                    Task { await manager.removeTomo(id: entry.id) }
                } label: {
                    Label("TOMOから削除", systemImage: "person.badge.minus")
                }
            }
        }
    }

    private func rankBadgeColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return Color.duoYellow
        case 2: return Color(hex: "#90A4AE")
        case 3: return Color.duoOrange
        default: return Color.duoBlue.opacity(0.55)
        }
    }
}
