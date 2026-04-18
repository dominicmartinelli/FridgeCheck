import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @State private var auth = AuthService.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 20) {
                Image(systemName: "refrigerator.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(Color.accentColor)

                Text("FridgeCheck")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Snap a photo of your fridge and get AI-powered recipe ideas.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            VStack(spacing: 16) {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    switch result {
                    case .success(let authorization):
                        if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                            Task { await auth.handleAppleCredential(credential) }
                        }
                    case .failure(let error):
                        if (error as? ASAuthorizationError)?.code != .canceled {
                            auth.errorMessage = error.localizedDescription
                        }
                    }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 50)
                .disabled(auth.isSigningIn)

                if auth.isSigningIn {
                    ProgressView()
                }

                if let err = auth.errorMessage {
                    Text(err)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Text("We use Sign in with Apple to keep your account secure. No passwords required.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
}

#Preview {
    SignInView()
}
