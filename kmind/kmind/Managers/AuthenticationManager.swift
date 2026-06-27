import Foundation
import GoogleSignIn
import UIKit
import Combine

@MainActor
final class AuthenticationManager: ObservableObject {
    static let shared = AuthenticationManager()

    @Published var isSignedIn: Bool = false
    @Published var currentUser: GIDGoogleUser? = nil
    @Published var errorMessage: String? = nil
    @Published var isLoading: Bool = false

    var displayName: String { currentUser?.profile?.name ?? "ゲスト" }
    var email: String { currentUser?.profile?.email ?? "" }
    var profileImageURL: URL? { currentUser?.profile?.imageURL(withDimension: 200) }

    private init() {
        // GIDClientID は Info.plist から SDK が自動読み込みするため設定不要
        // 前回のサインイン状態を確認
        currentUser = GIDSignIn.sharedInstance.currentUser
        isSignedIn = currentUser != nil
    }

    func restorePreviousSignIn() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            currentUser = user
            isSignedIn = true
        } catch {
            isSignedIn = false
        }
    }

    func signIn() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        guard let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            errorMessage = "画面の取得に失敗しました"
            return
        }

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)
            currentUser = result.user
            isSignedIn = true
        } catch {
            let nsError = error as NSError
            // ユーザーが自分でキャンセルした場合はエラー表示しない
            if nsError.code != GIDSignInError.canceled.rawValue {
                errorMessage = error.localizedDescription
            }
        }
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        currentUser = nil
        isSignedIn = false
    }
}
