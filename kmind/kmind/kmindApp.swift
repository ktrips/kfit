import SwiftUI
import GoogleSignIn

// MARK: - グローバル設定キー
extension AppStorageKey {
    static let colorScheme    = "kmind.colorScheme"
    static let sleepHoursGoal = "kmind.sleepHoursGoal"
}

enum AppStorageKey {}

// MARK: - kmind アプリ エントリーポイント
// kfit の MIND ページ・関連 Setup を単独アプリとして起動します。
// 参照しているソースファイルは ios/kfit/ に物理的に存在し、
// kmind.xcodeproj では「参照追加（コピーなし）」で取り込みます。
//
// Firebase を使う場合は:
//   File → Add Package Dependencies → https://github.com/firebase/firebase-ios-sdk
//   その後 import Firebase と FirebaseApp.configure() を復元してください。

@main
struct kmindApp: App {

    // MARK: 共有シングルトン
    @StateObject private var auth          = AuthenticationManager.shared
    @StateObject private var healthKit     = HealthKitManager.shared
    @StateObject private var timeSlotMgr   = TimeSlotManager.shared
    @StateObject private var plus          = PlusManager.shared

    @AppStorage(AppStorageKey.colorScheme) private var colorSchemePref = "system"

    private var preferredColorScheme: ColorScheme? {
        switch colorSchemePref {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isSignedIn {
                    kmindContentView()
                        .environmentObject(healthKit)
                        .environmentObject(timeSlotMgr)
                        .environmentObject(plus)
                        .environmentObject(auth)
                } else {
                    LoginView()
                        .environmentObject(auth)
                }
            }
            .preferredColorScheme(preferredColorScheme)
            .task {
                // アプリ起動時に前回のサインイン状態を復元
                await auth.restorePreviousSignIn()
            }
            // Google Sign-In の URL ハンドリング
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
        }
    }
}

// MARK: - コンテンツルート（タブバーなし）
struct kmindContentView: View {
    @EnvironmentObject private var plus: PlusManager
    @EnvironmentObject private var auth: AuthenticationManager

    var body: some View {
        MindView(selectedTab: .constant(0), showRecordMenu: .constant(false))
    }
}

// MARK: - kmind 専用設定画面
struct kmindSettingsView: View {
    @EnvironmentObject private var plus: PlusManager
    @EnvironmentObject private var auth: AuthenticationManager
    @State private var showSignOutConfirm = false

    @AppStorage(AppStorageKey.colorScheme)    private var colorSchemePref  = "system"
    @AppStorage(AppStorageKey.sleepHoursGoal) private var sleepHoursGoal   = 7

    var body: some View {
        NavigationView {
            List {
                // アカウント情報
                Section("アカウント") {
                    HStack(spacing: 12) {
                        AsyncImage(url: auth.profileImageURL) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Image(systemName: "person.circle.fill")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(auth.displayName)
                                .font(.headline)
                            Text(auth.email)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)

                    Button(role: .destructive) {
                        showSignOutConfirm = true
                    } label: {
                        Label("ログアウト", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }

                Section("プラン") {
                    if plus.isPlus {
                        HStack {
                            Label("kmind Plus 有効", systemImage: "crown.fill")
                                .foregroundStyle(.orange)
                            Spacer()
                            if plus.codeUnlocked {
                                Text("コード解除")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        NavigationLink {
                            PlusView().environmentObject(plus)
                        } label: {
                            Label("Plusにアップグレード", systemImage: "crown")
                        }
                    }
                }
                // テーマ設定
                Section("外観") {
                    Picker(selection: $colorSchemePref) {
                        Label("システム設定に合わせる", systemImage: "circle.lefthalf.filled")
                            .tag("system")
                        Label("ライト", systemImage: "sun.max.fill")
                            .tag("light")
                        Label("ダーク", systemImage: "moon.fill")
                            .tag("dark")
                    } label: {
                        Label("テーマ", systemImage: "paintpalette")
                    }
                    .pickerStyle(.navigationLink)
                }

                // 睡眠目標
                Section {
                    Stepper(
                        value: $sleepHoursGoal,
                        in: 4...12
                    ) {
                        HStack {
                            Label("目標睡眠時間", systemImage: "moon.zzz.fill")
                                .foregroundStyle(.indigo)
                            Spacer()
                            Text("\(sleepHoursGoal) 時間")
                                .font(.headline)
                                .foregroundStyle(.indigo)
                        }
                    }
                } header: {
                    Text("睡眠")
                } footer: {
                    Text("この時間を基準に睡眠スコアを計算します（kfit のデフォルトと同じ 7 時間）")
                }

                Section("HealthKit") {
                    Label("睡眠・HRV・マインドフルネス", systemImage: "heart.fill")
                        .foregroundStyle(.red)
                    Text("Apple ヘルスケアアプリの権限が必要です")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("このアプリについて") {
                    LabeledContent("バージョン", value: "1.0.0")
                    LabeledContent("kfit との連携", value: "同一コードベース")
                    Text("kmind は kfit の MIND 機能を単独アプリとして提供します。設定・データはそれぞれ独立しています。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("設定")
            .confirmationDialog("ログアウトしますか？", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
                Button("ログアウト", role: .destructive) {
                    auth.signOut()
                }
                Button("キャンセル", role: .cancel) {}
            }
        }
    }
}
