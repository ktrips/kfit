import SwiftUI
import UserNotifications

// MARK: - リマインダーメタデータ

private struct ReminderMeta: Identifiable {
    let id: String
    let emoji: String
    let label: String
    let description: String
}

private let reminderItems: [ReminderMeta] = [
    ReminderMeta(id: NotificationManager.ID.amReminder,
                 emoji: "🌅", label: "朝のリマインダー",
                 description: "朝トレを始めるタイミングで通知"),
    ReminderMeta(id: NotificationManager.ID.amFollowup,
                 emoji: "🔥", label: "朝のフォローアップ",
                 description: "朝トレをまだしていない場合に再通知"),
    ReminderMeta(id: NotificationManager.ID.pmReminder,
                 emoji: "🌆", label: "夕方のリマインダー",
                 description: "2セット目のタイミングで通知"),
    ReminderMeta(id: NotificationManager.ID.pmFollowup,
                 emoji: "⚡", label: "夕方のフォローアップ",
                 description: "夜トレをまだしていない場合に再通知"),
    ReminderMeta(id: NotificationManager.ID.streakAlert,
                 emoji: "🚨", label: "ストリーク警告",
                 description: "その日まだ記録がない場合に最終警告"),
]

// MARK: - SettingsView

struct SettingsView: View {
    @StateObject private var notif = NotificationManager.shared
    @State private var watchAutoLaunch = iOSWatchBridge.isWatchAutoLaunchEnabled
    @State private var permStatus: UNAuthorizationStatus = .notDetermined
    @State private var showHabitStack = false
    @State private var showShortcutsGuide = false
    @State private var savedBanner = false

    var body: some View {
        ZStack {
            Color.duoBg.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    headerSection
                    permissionBanner
                    reminderSection
                    watchSection
                    habitStackSection
                    linkedAppsSection
                    saveButton
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
        }
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshPermStatus() }
        .sheet(isPresented: $showHabitStack) { NavigationView { HabitStackView() } }
        .sheet(isPresented: $showShortcutsGuide) { ShortcutsGuideView() }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 12) {
            Image("mascot")
                .resizable().scaledToFill()
                .frame(width: 52, height: 52)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.duoGreen, lineWidth: 2))
            VStack(alignment: .leading, spacing: 2) {
                Text("設定")
                    .font(.title3).fontWeight(.black).foregroundColor(Color.duoDark)
                Text("通知・連動起動のカスタマイズ")
                    .font(.caption).foregroundColor(Color.duoSubtitle)
            }
            Spacer()
        }
        .padding(.top, 4)
    }

    // MARK: - 通知権限バナー

    private var permissionBanner: some View {
        Group {
            switch permStatus {
            case .denied:
                HStack(spacing: 10) {
                    Text("🚫").font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("通知がブロックされています")
                            .font(.subheadline).fontWeight(.black)
                            .foregroundColor(Color(hex: "#7f0000"))
                        Text("設定アプリ → DuoFit → 通知 から許可してください")
                            .font(.caption)
                            .foregroundColor(Color(hex: "#7f0000"))
                    }
                    Spacer()
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("設定へ")
                            .font(.caption).fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color.red)
                            .cornerRadius(8)
                    }
                }
                .padding(14)
                .background(Color(hex: "#FCE4EC"))
                .cornerRadius(14)

            case .notDetermined:
                Button {
                    Task {
                        await notif.requestPermission()
                        await refreshPermStatus()
                        if permStatus == .authorized { notif.scheduleAllDaily() }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bell.badge.fill")
                        Text("通知を有効にする")
                            .fontWeight(.black)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.duoGreen)
                    .cornerRadius(14)
                }
                .buttonStyle(.plain)

            default:
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color.duoGreen)
                    Text("通知が有効です")
                        .font(.subheadline).fontWeight(.black).foregroundColor(Color.duoGreen)
                    Spacer()
                    Button {
                        notif.scheduleAllDaily()
                        notif.savePrefs()
                    } label: {
                        Text("テスト再スケジュール")
                            .font(.caption).fontWeight(.bold)
                            .foregroundColor(Color.duoGreen)
                            .underline()
                    }
                }
                .padding(12)
                .background(Color(hex: "#D7FFB8"))
                .cornerRadius(14)
            }
        }
    }

    // MARK: - リマインダーセクション

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(icon: "bell.fill", title: "リマインダー",
                          subtitle: "時間と有効/無効を設定")

            VStack(spacing: 0) {
                ForEach(Array(reminderItems.enumerated()), id: \.element.id) { idx, meta in
                    ReminderRow(
                        meta: meta,
                        config: Binding(
                            get: { notif.prefs[meta.id] },
                            set: { notif.prefs[meta.id] = $0 }
                        )
                    )
                    if idx < reminderItems.count - 1 {
                        Divider().padding(.leading, 56)
                    }
                }
            }
            .background(Color.white)
            .cornerRadius(14)
            .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
        }
    }

    // MARK: - Apple Watch セクション

    private var watchSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(icon: "applewatch", title: "Apple Watch",
                          subtitle: "Watch連携の動作設定")

            VStack(spacing: 0) {
                // 自動起動トグル
                HStack(spacing: 12) {
                    Image(systemName: "applewatch.radiowaves.left.and.right")
                        .font(.title3)
                        .foregroundColor(Color.duoGreen)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("自動ワークアウト起動")
                            .font(.subheadline).fontWeight(.bold).foregroundColor(Color.duoDark)
                        Text("iOSアプリを開いたとき、Watchのワークアウトを自動開始")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                            .lineLimit(2)
                    }
                    Spacer()
                    Toggle("", isOn: $watchAutoLaunch)
                        .tint(Color.duoGreen)
                        .labelsHidden()
                }
                .padding(14)

                // 説明バナー
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .font(.caption).foregroundColor(Color(hex: "#1CB0F6"))
                    Text("Watch側のアプリが起動済みのとき、iOSアプリを開くと同時にワークアウト画面へ自動遷移します")
                        .font(.caption).foregroundColor(Color(hex: "#0a6c96"))
                }
                .padding(.horizontal, 14).padding(.bottom, 12)
            }
            .background(Color.white)
            .cornerRadius(14)
            .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
        }
    }

    // MARK: - ハビットスタックセクション

    private var habitStackSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(icon: "link.circle.fill", title: "ハビットスタック",
                          subtitle: "既存の日課とトレーニングをセット")

            Button { showHabitStack = true } label: {
                HStack(spacing: 12) {
                    Text("🔗").font(.title3).frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ハビットスタックを管理")
                            .font(.subheadline).fontWeight(.bold).foregroundColor(Color.duoDark)
                        Text("歯磨き・シャワーなどの日課の後に通知")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Color.duoSubtitle)
                }
                .padding(14)
                .background(Color.white)
                .cornerRadius(14)
                .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 連動アプリセクション

    private var linkedAppsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(icon: "square.stack.3d.up.fill", title: "連動アプリ",
                          subtitle: "他のアプリを開いたときDuoFitを起動")

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("🦉").font(.title3).frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("iOSショートカットで自動化")
                            .font(.subheadline).fontWeight(.bold).foregroundColor(Color.duoDark)
                        Text("Duolingoなどを開いたとき、DuoFitも自動起動")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                    }
                    Spacer()
                    Button { showShortcutsGuide = true } label: {
                        Text("設定方法")
                            .font(.caption).fontWeight(.bold)
                            .foregroundColor(Color.duoGreen)
                            .underline()
                    }
                }
                .padding(14)
            }
            .background(Color.white)
            .cornerRadius(14)
            .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
        }
    }

    // MARK: - 保存ボタン

    private var saveButton: some View {
        Button {
            notif.savePrefs()
            iOSWatchBridge.isWatchAutoLaunchEnabled = watchAutoLaunch
            if permStatus == .authorized { notif.scheduleAllDaily() }
            withAnimation { savedBanner = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation { savedBanner = false }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: savedBanner ? "checkmark.circle.fill" : "square.and.arrow.down.fill")
                Text(savedBanner ? "保存しました！" : "設定を保存")
                    .fontWeight(.black)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(savedBanner ? Color(hex: "#46A302") : Color.duoGreen)
            .cornerRadius(14)
            .shadow(color: Color.duoGreen.opacity(0.3), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    // MARK: - Helpers

    private func sectionHeader(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(Color.duoGreen)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.subheadline).fontWeight(.black).foregroundColor(Color.duoDark)
                Text(subtitle)
                    .font(.caption2).foregroundColor(Color.duoSubtitle)
            }
        }
        .padding(.bottom, 8)
    }

    private func refreshPermStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        permStatus = settings.authorizationStatus
    }
}

// MARK: - ReminderRow

private struct ReminderRow: View {
    let meta: ReminderMeta
    @Binding var config: ReminderConfig
    @State private var time: Date = Date()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(meta.emoji).font(.title3).frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(meta.label)
                        .font(.subheadline).fontWeight(.bold).foregroundColor(Color.duoDark)
                    Text(meta.description)
                        .font(.caption).foregroundColor(Color.duoSubtitle)
                }
                Spacer()
                Toggle("", isOn: $config.enabled)
                    .tint(Color.duoGreen)
                    .labelsHidden()
            }
            .padding(.horizontal, 14).padding(.vertical, 12)

            if config.enabled {
                HStack(spacing: 10) {
                    Image(systemName: "clock")
                        .font(.caption).foregroundColor(Color.duoSubtitle)
                    DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .tint(Color.duoGreen)
                        .onChange(of: time) { newVal in
                            let comps = Calendar.current.dateComponents([.hour, .minute], from: newVal)
                            config.hour   = comps.hour   ?? config.hour
                            config.minute = comps.minute ?? config.minute
                        }
                    Spacer()
                    Text(String(format: "毎日 %02d:%02d", config.hour, config.minute))
                        .font(.caption).foregroundColor(Color.duoSubtitle)
                }
                .padding(.horizontal, 14).padding(.bottom, 12)
                .background(Color(hex: "#F0FFF0"))
            }
        }
        .onAppear {
            // config の hour/minute → Date に変換して DatePicker に渡す
            time = Calendar.current.date(
                bySettingHour: config.hour, minute: config.minute, second: 0, of: Date()
            ) ?? Date()
        }
    }
}

// MARK: - ShortcutsGuideView

private struct ShortcutsGuideView: View {
    @Environment(\.dismiss) private var dismiss

    private let steps = [
        ("iPhoneの「ショートカット」アプリを開く", "app.badge"),
        ("「オートメーション」タブ → 右上の「＋」", "plus.circle"),
        ("「App」を選択 → 連動させたいアプリ（例: Duolingo）を選ぶ", "app.connected.to.app.below.fill"),
        ("「開いたとき」を選択 → 「次へ」", "chevron.right.circle"),
        ("「アクションを追加」→「URLを開く」→ duofit:// を入力", "link"),
        ("「完了」で保存", "checkmark.circle.fill"),
    ]

    var body: some View {
        NavigationView {
            ZStack {
                Color.duoBg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("iOSショートカットで\n他のアプリと連動させる方法")
                            .font(.title3).fontWeight(.black)
                            .foregroundColor(Color.duoDark)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)

                        ForEach(Array(steps.enumerated()), id: \.offset) { idx, step in
                            HStack(alignment: .top, spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(Color.duoGreen)
                                        .frame(width: 28, height: 28)
                                    Text("\(idx + 1)")
                                        .font(.caption).fontWeight(.black).foregroundColor(.white)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(step.0)
                                        .font(.subheadline).fontWeight(.bold)
                                        .foregroundColor(Color.duoDark)
                                    Image(systemName: step.1)
                                        .font(.caption)
                                        .foregroundColor(Color.duoSubtitle)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                        }

                        Text("設定後はDuolingoを開くとDuoFitが自動的に前面に出てきます")
                            .font(.caption)
                            .foregroundColor(Color.duoSubtitle)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)

                        Spacer(minLength: 40)
                    }
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("ショートカット設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") { dismiss() }
                        .foregroundColor(Color.duoGreen)
                }
            }
        }
    }
}

#Preview {
    NavigationView { SettingsView() }
}
