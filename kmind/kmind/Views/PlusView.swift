import SwiftUI

// MARK: - kmind Plus アップグレード画面
// kfit の PlusView（Firebase/StoreKit）の代わりに使用する独立実装です。

struct PlusView: View {
    @EnvironmentObject private var plus: PlusManager
    @Environment(\.dismiss) private var dismiss

    @State private var codeInput = ""
    @State private var showCodeField = false
    @State private var isFetchingCode = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {

                    // MARK: ヘッダー
                    VStack(spacing: 8) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.orange)
                            .padding(.top, 24)

                        Text("kmind Plus")
                            .font(.largeTitle.bold())

                        Text("睡眠・HRV・マインドフルネスの\n詳細分析でより深い自己理解を")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    // MARK: 機能一覧
                    VStack(spacing: 0) {
                    ForEach(Array(features.enumerated()), id: \.offset) { idx, feature in
                        HStack(spacing: 14) {
                            Image(systemName: feature.icon)
                                .font(.title3)
                                .foregroundStyle(.purple)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(feature.title)
                                    .font(.subheadline.bold())
                                Text(feature.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        if idx < features.count - 1 {
                            Divider().padding(.leading, 62)
                        }
                    }
                    }
                    .background(.background, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)

                    // MARK: 購入ボタン（Coming Soon）
                    VStack(spacing: 12) {
                        Button {
                            // TODO: StoreKit 購入フロー
                        } label: {
                            VStack(spacing: 4) {
                                Text("月額プランを購入")
                                    .font(.headline)
                                Text("準備中")
                                    .font(.caption)
                                    .opacity(0.8)
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.orange, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(true)
                        .opacity(0.6)
                        .padding(.horizontal)

                        // コードアンロック
                        codeUnlockSection
                    }

                    Spacer(minLength: 32)
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Plus にアップグレード")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isFetchingCode {
                        ProgressView()
                    }
                }
            }
            .task {
                // 画面表示のたびに Firestore から最新コードを取得
                isFetchingCode = true
                await plus.fetchSecretCode()
                isFetchingCode = false
            }
        }
    }

    // MARK: - コードアンロックセクション（kfit と共通のコードで解除）
    @ViewBuilder
    private var codeUnlockSection: some View {
        if showCodeField {
            VStack(spacing: 10) {
                SecureField("Plusコードを入力", text: $codeInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)

                if let err = plus.purchaseError {
                    Label(err, systemImage: "xmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                }

                HStack {
                    Button("キャンセル") {
                        showCodeField = false
                        codeInput = ""
                        plus.purchaseError = nil
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    Spacer()

                    Button("解放する") {
                        Task {
                            // 送信直前にも最新コードを再取得してから照合
                            await plus.fetchSecretCode()
                            let ok = plus.unlockWithCode(codeInput)
                            if ok {
                                try? await Task.sleep(for: .milliseconds(800))
                                dismiss()
                            }
                        }
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        codeInput.isEmpty ? Color(.systemGray4) : Color.orange,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .disabled(codeInput.isEmpty)
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 4)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal)
        } else {
            Button("コードをお持ちの方") {
                showCodeField = true
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private struct Feature {
        let title: String
        let icon: String
        let description: String
    }

    private var features: [Feature] {
        [
            Feature(title: "HRV 詳細グラフ",      icon: "waveform.path.ecg",         description: "7日間の心拍変動トレンドを可視化"),
            Feature(title: "睡眠ステージ分析",     icon: "moon.stars.fill",            description: "深眠・REM・浅眠の内訳を詳細表示"),
            Feature(title: "ストレスインサイト",   icon: "chart.line.uptrend.xyaxis",  description: "HRV から導くストレス傾向レポート"),
            Feature(title: "無制限セッション記録", icon: "brain.head.profile",         description: "マインドフルネス履歴を無制限保存"),
            Feature(title: "Watch 連携",           icon: "applewatch",                 description: "Apple Watch でリアルタイムモニタリング"),
        ]
    }
}

#Preview {
    PlusView()
        .environmentObject(PlusManager.shared)
}
