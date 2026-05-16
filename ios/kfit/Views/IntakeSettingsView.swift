import SwiftUI

struct IntakeSettingsView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss

    @State private var settings = IntakeSettings.defaultSettings
    @State private var isLoading = true
    @State private var isSaving = false

    var body: some View {
        NavigationView {
            Form {
                // 食事のカロリー設定
                Section {
                    HStack {
                        Text("🌅 朝食")
                            .font(.subheadline).fontWeight(.bold)
                        Spacer()
                        TextField("", value: $settings.breakfastCalories, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("kcal")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                    }

                    HStack {
                        Text("🍱 昼食")
                            .font(.subheadline).fontWeight(.bold)
                        Spacer()
                        TextField("", value: $settings.lunchCalories, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("kcal")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                    }

                    HStack {
                        Text("🍽️ 夕食")
                            .font(.subheadline).fontWeight(.bold)
                        Spacer()
                        TextField("", value: $settings.dinnerCalories, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("kcal")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                    }
                } header: {
                    Text("食事のデフォルトカロリー")
                }

                // 水分設定
                Section {
                    HStack {
                        Text("💧 水1杯")
                            .font(.subheadline).fontWeight(.bold)
                        Spacer()
                        TextField("", value: $settings.waterPerCup, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("ml")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                    }
                } header: {
                    Text("水分")
                }

                // コーヒー設定
                Section {
                    HStack {
                        Text("☕ コーヒー1杯")
                            .font(.subheadline).fontWeight(.bold)
                        Spacer()
                        TextField("", value: $settings.coffeePerCup, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("ml")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                    }

                    HStack {
                        Text("カフェイン量")
                            .font(.subheadline).fontWeight(.bold)
                        Spacer()
                        TextField("", value: $settings.caffeinePerCup, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("mg")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                    }
                } header: {
                    Text("コーヒー")
                }

                // 1日の目標値
                Section {
                    HStack {
                        Text("🎯 カロリー目標")
                            .font(.subheadline).fontWeight(.bold)
                        Spacer()
                        TextField("", value: $settings.dailyCalorieGoal, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("kcal")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                    }

                    HStack {
                        Text("💧 水分目標")
                            .font(.subheadline).fontWeight(.bold)
                        Spacer()
                        TextField("", value: $settings.dailyWaterGoal, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("ml")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                    }

                    HStack {
                        Text("☕ カフェイン上限")
                            .font(.subheadline).fontWeight(.bold)
                        Spacer()
                        TextField("", value: $settings.dailyCaffeineLimit, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("mg")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                    }

                    HStack {
                        Text("🍺 アルコール上限")
                            .font(.subheadline).fontWeight(.bold)
                        Spacer()
                        TextField("", value: $settings.dailyAlcoholLimit, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("g")
                            .font(.caption).foregroundColor(Color.duoSubtitle)
                    }
                } header: {
                    Text("1日の目標")
                }

                // アルコール設定
                Section {
                    ForEach($settings.alcoholSettings) { $alcoholSetting in
                        VStack(spacing: 8) {
                            HStack {
                                Text("\(alcoholSetting.type.emoji) \(alcoholSetting.displayName)")
                                    .font(.subheadline).fontWeight(.bold)
                                Spacer()
                            }

                            HStack {
                                Text("量")
                                    .font(.caption).foregroundColor(Color.duoSubtitle)
                                Spacer()
                                TextField("", value: $alcoholSetting.amountMl, format: .number)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 60)
                                Text("ml")
                                    .font(.caption2).foregroundColor(Color.duoSubtitle)
                            }

                            HStack {
                                Text("アルコール")
                                    .font(.caption).foregroundColor(Color.duoSubtitle)
                                Spacer()
                                TextField("", value: $alcoholSetting.alcoholG, format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 60)
                                Text("g")
                                    .font(.caption2).foregroundColor(Color.duoSubtitle)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("アルコール")
                }

                // リセットボタン
                Section {
                    Button {
                        settings = IntakeSettings.defaultSettings
                    } label: {
                        HStack {
                            Spacer()
                            Text("デフォルトに戻す")
                                .font(.subheadline).fontWeight(.bold)
                                .foregroundColor(Color.duoOrange)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("摂取記録設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            isSaving = true
                            await authManager.saveIntakeSettings(settings)
                            isSaving = false
                            dismiss()
                        }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("保存")
                                .fontWeight(.bold)
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .task {
                settings = await authManager.getIntakeSettings()
                isLoading = false
            }
        }
    }
}

#Preview {
    IntakeSettingsView()
        .environmentObject(AuthenticationManager.shared)
}
import SwiftUI

struct LLMSettingsView: View {
    @StateObject private var authManager = AuthenticationManager.shared
    @State private var settings = LLMSettings.defaultSettings
    @State private var showSaveConfirmation = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.duoBg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    headerSection
                    providerSection
                    apiKeySection
                    modelSection
                    saveButton

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
        }
        .navigationTitle("LLM設定")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            settings = await authManager.getLLMSettings()
        }
        .alert("保存しました", isPresented: $showSaveConfirmation) {
            Button("OK", role: .cancel) { }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.duoGreen, Color(hex: "#58CC02").opacity(0.7)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 52, height: 52)
                    Image(systemName: "brain.head.profile")
                        .font(.title3)
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("フォトログAI設定")
                        .font(.title3).fontWeight(.black).foregroundColor(Color.duoDark)
                    Text("写真から栄養素を分析")
                        .font(.caption).foregroundColor(Color.duoSubtitle)
                }
                Spacer()
            }

            Text("写真を撮影すると、AIが食品を認識してカロリーや栄養素を自動で推定します。")
                .font(.caption)
                .foregroundColor(Color.duoSubtitle)
                .padding(.top, 4)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Provider Section

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(icon: "🤖", title: "AIプロバイダー")

            ForEach(LLMProvider.allCases, id: \.self) { provider in
                Button {
                    settings.provider = provider
                    settings.model = ""  // モデルをリセット
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.displayName)
                                .font(.subheadline).fontWeight(.semibold)
                                .foregroundColor(Color.duoDark)
                            Text("デフォルト: \(provider.rawValue == settings.provider.rawValue ? settings.defaultModel : LLMSettings(provider: provider, apiKey: "", model: "").defaultModel)")
                                .font(.caption2)
                                .foregroundColor(Color.duoSubtitle)
                        }
                        Spacer()
                        if provider == settings.provider {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Color.duoGreen)
                        } else {
                            Image(systemName: "circle")
                                .foregroundColor(Color.duoSubtitle)
                        }
                    }
                    .padding(12)
                    .background(provider == settings.provider ? Color.duoGreen.opacity(0.1) : Color.white)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }

            Text("最もリーズナブルなモデルを自動選択します")
                .font(.caption)
                .foregroundColor(Color.duoSubtitle)
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
    }

    // MARK: - API Key Section

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(icon: "🔑", title: "APIキー")

            VStack(alignment: .leading, spacing: 8) {
                Text("APIキーを入力")
                    .font(.caption)
                    .foregroundColor(Color.duoSubtitle)

                SecureField("sk-...", text: $settings.apiKey)
                    .font(.caption)
                    .padding(12)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
            }

            Text("APIキーは暗号化して安全に保存されます。外部に送信されることはありません。")
                .font(.caption)
                .foregroundColor(Color.duoSubtitle)

            // API取得リンク
            Link(destination: URL(string: apiKeyURL)!) {
                HStack {
                    Image(systemName: "arrow.up.right.square")
                    Text("APIキーを取得する")
                        .fontWeight(.semibold)
                }
                .font(.caption)
                .foregroundColor(Color.duoGreen)
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
    }

    // MARK: - Model Section

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(icon: "⚙️", title: "モデル（オプション）")

            VStack(alignment: .leading, spacing: 8) {
                Text("カスタムモデルを指定（空欄でデフォルト）")
                    .font(.caption)
                    .foregroundColor(Color.duoSubtitle)

                TextField("例: \(settings.defaultModel)", text: $settings.model)
                    .font(.caption)
                    .padding(12)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
            }

            Text("空欄の場合、最もリーズナブルなモデルが自動選択されます: \(settings.defaultModel)")
                .font(.caption)
                .foregroundColor(Color.duoSubtitle)
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
    }

    // MARK: - Save Button

    private var saveButton: some View {
        Button {
            Task {
                await authManager.saveLLMSettings(settings)
                showSaveConfirmation = true
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                Text("保存する")
                    .fontWeight(.black)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.duoGreen)
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func sectionTitle(icon: String, title: String) -> some View {
        HStack(spacing: 8) {
            Text(icon)
                .font(.title3)
            Text(title)
                .font(.headline)
                .fontWeight(.black)
                .foregroundColor(Color.duoDark)
        }
    }

    private var apiKeyURL: String {
        switch settings.provider {
        case .openAI:
            return "https://platform.openai.com/api-keys"
        case .anthropic:
            return "https://console.anthropic.com/settings/keys"
        case .google:
            return "https://aistudio.google.com/app/apikey"
        }
    }
}

#Preview {
    NavigationView {
        LLMSettingsView()
    }
}
