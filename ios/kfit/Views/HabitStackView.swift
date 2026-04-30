import SwiftUI

/// 習慣スタック管理画面
/// - 習慣一覧の表示・有効/無効切り替え・削除
/// - 新規追加（プリセット or カスタム）
struct HabitStackView: View {
    @StateObject private var manager = HabitStackManager.shared
    @State private var showAddSheet  = false

    var body: some View {
        ZStack {
            Color.duoBg.ignoresSafeArea()

            if manager.habits.isEmpty {
                emptyState
            } else {
                habitList
            }
        }
        .navigationTitle("ハビットスタック")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(Color.duoGreen)
                        .font(.title3)
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddHabitView()
        }
    }

    // MARK: - 習慣一覧

    private var habitList: some View {
        ScrollView {
            VStack(spacing: 0) {
                // 説明バナー
                descriptionBanner
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                LazyVStack(spacing: 10) {
                    ForEach(manager.habits) { habit in
                        habitRow(habit)
                    }
                }
                .padding(.horizontal, 16)

                addButton
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
            }
        }
    }

    private func habitRow(_ habit: HabitStack) -> some View {
        HStack(spacing: 12) {
            // アイコン
            Text(habit.emoji)
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(Color.duoGreen.opacity(habit.isEnabled ? 0.12 : 0.05))
                .clipShape(Circle())

            // 名前 + 時刻
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.name)
                    .font(.subheadline).fontWeight(.bold)
                    .foregroundColor(habit.isEnabled ? Color.duoDark : Color.duoSubtitle)
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text(habit.timeString)
                        .font(.caption)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                    Image(systemName: "figure.run")
                        .font(.caption2)
                    Text("トレーニング")
                        .font(.caption)
                }
                .foregroundColor(habit.isEnabled ? Color.duoGreen : Color.duoSubtitle)
            }

            Spacer()

            // 有効/無効トグル
            Toggle("", isOn: Binding(
                get: { habit.isEnabled },
                set: { _ in manager.toggle(id: habit.id) }
            ))
            .tint(Color.duoGreen)
            .labelsHidden()
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
        .opacity(habit.isEnabled ? 1.0 : 0.6)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                withAnimation { manager.remove(id: habit.id) }
            } label: {
                Label("削除", systemImage: "trash")
            }
        }
    }

    // MARK: - 空の状態

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("🔗")
                .font(.system(size: 64))
            Text("習慣スタックを設定しよう")
                .font(.headline).fontWeight(.black)
                .foregroundColor(Color.duoDark)
            Text("既存の日課（歯磨きなど）と\nトレーニングをセットにすることで\n続けやすくなります")
                .font(.subheadline)
                .foregroundColor(Color.duoSubtitle)
                .multilineTextAlignment(.center)
            addButton
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    // MARK: - パーツ

    private var descriptionBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .foregroundColor(Color.duoYellow)
            Text("日課の後にリマインダーが届き、トレーニングを促します")
                .font(.caption)
                .foregroundColor(Color.duoDark)
        }
        .padding(12)
        .background(Color.duoYellow.opacity(0.12))
        .cornerRadius(10)
    }

    private var addButton: some View {
        Button {
            showAddSheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                Text("ハビットを追加")
                    .fontWeight(.bold)
            }
            .foregroundColor(Color.duoGreen)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.duoGreen.opacity(0.10))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 新規追加シート

struct AddHabitView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = HabitStackManager.shared

    @State private var selectedEmoji = "🦷"
    @State private var name          = ""
    @State private var time          = Calendar.current.date(
        bySettingHour: 7, minute: 30, second: 0, of: Date()
    ) ?? Date()
    @State private var showPresets   = true

    private let emojiOptions = ["🦷","☕️","🚿","🌙","📱","🚌","🏠","🍽️","📚","🛏️","🐕","🎮"]

    var body: some View {
        NavigationView {
            ZStack {
                Color.duoBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        // プリセット選択
                        if showPresets {
                            presetSection
                        }

                        // カスタム入力
                        customSection

                        // 追加ボタン
                        addButton
                            .padding(.bottom, 30)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
            }
            .navigationTitle("ハビットを追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") { dismiss() }
                        .foregroundColor(Color.duoSubtitle)
                }
            }
        }
    }

    // MARK: - プリセット

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("よく使う日課")
                .font(.subheadline).fontWeight(.black)
                .foregroundColor(Color.duoDark)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(HabitStack.presets, id: \.name) { preset in
                    Button {
                        selectedEmoji = preset.emoji
                        name = preset.name
                        time = Calendar.current.date(
                            bySettingHour: preset.hour,
                            minute: preset.minute,
                            second: 0, of: Date()
                        ) ?? Date()
                        showPresets = false
                    } label: {
                        HStack(spacing: 8) {
                            Text(preset.emoji).font(.title3)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(preset.name)
                                    .font(.caption).fontWeight(.bold)
                                    .foregroundColor(Color.duoDark)
                                Text(String(format: "%02d:%02d", preset.hour, preset.minute))
                                    .font(.caption2)
                                    .foregroundColor(Color.duoSubtitle)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(Color.white)
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.04), radius: 3, y: 1)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                withAnimation { showPresets = false }
            } label: {
                Text("カスタムで入力する")
                    .font(.caption)
                    .foregroundColor(Color.duoSubtitle)
                    .underline()
            }
        }
    }

    // MARK: - カスタム入力

    private var customSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(showPresets ? "または自分で設定" : "カスタム設定")
                .font(.subheadline).fontWeight(.black)
                .foregroundColor(Color.duoDark)

            // 絵文字選択
            VStack(alignment: .leading, spacing: 8) {
                Text("アイコン").font(.caption).foregroundColor(Color.duoSubtitle)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(emojiOptions, id: \.self) { emoji in
                            Button {
                                selectedEmoji = emoji
                            } label: {
                                Text(emoji)
                                    .font(.title2)
                                    .frame(width: 44, height: 44)
                                    .background(
                                        selectedEmoji == emoji
                                            ? Color.duoGreen.opacity(0.20)
                                            : Color.white
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(
                                                selectedEmoji == emoji
                                                    ? Color.duoGreen
                                                    : Color(.systemGray5),
                                                lineWidth: 1.5
                                            )
                                    )
                                    .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // 名前入力
            VStack(alignment: .leading, spacing: 6) {
                Text("日課の名前").font(.caption).foregroundColor(Color.duoSubtitle)
                TextField("例: 歯磨き、シャワー", text: $name)
                    .padding(12)
                    .background(Color.white)
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.systemGray4), lineWidth: 1))
            }

            // 時刻選択
            VStack(alignment: .leading, spacing: 6) {
                Text("時刻（この時刻にリマインダーが届く）").font(.caption).foregroundColor(Color.duoSubtitle)
                DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .background(Color.white)
                    .cornerRadius(10)
            }
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)
    }

    // MARK: - 追加ボタン

    private var addButton: some View {
        Button {
            guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            let comps = Calendar.current.dateComponents([.hour, .minute], from: time)
            let habit = HabitStack(
                emoji:   selectedEmoji,
                name:    name.trimmingCharacters(in: .whitespaces),
                hour:    comps.hour ?? 7,
                minute:  comps.minute ?? 0
            )
            manager.add(habit)
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                Text("追加する")
                    .fontWeight(.black)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                name.trimmingCharacters(in: .whitespaces).isEmpty
                    ? Color(.systemGray4)
                    : Color.duoGreen
            )
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
    }
}

#Preview {
    NavigationView { HabitStackView() }
}
