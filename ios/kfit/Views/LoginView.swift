import SwiftUI
import GoogleSignIn

struct LoginView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var isLoading = false

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [.blue, .purple]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // Logo and title
                VStack(spacing: 12) {
                    Text("kfit")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(.white)

                    Text("Build fitness habits like Duolingo")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }

                Spacer()

                // Description
                VStack(spacing: 16) {
                    Text("Track your push-ups, squats, and sit-ups. Build streaks. Earn achievements.")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()

                // Sign in button
                Button(action: signInWithGoogle) {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        HStack(spacing: 12) {
                            Image(systemName: "g.circle.fill")
                            Text("Sign in with Google")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.blue.opacity(0.8))
                        .cornerRadius(12)
                    }
                }
                .disabled(isLoading)
                .padding(.horizontal, 20)

                Spacer()

                // Error message
                if let error = authManager.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal, 20)
                }
            }
            .padding(.vertical, 40)
        }
    }

    private func signInWithGoogle() {
        isLoading = true
        Task {
            let success = await authManager.signInWithGoogle()
            isLoading = false

            if !success && authManager.errorMessage == nil {
                authManager.errorMessage = "Sign in failed"
            }
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthenticationManager.shared)
}
