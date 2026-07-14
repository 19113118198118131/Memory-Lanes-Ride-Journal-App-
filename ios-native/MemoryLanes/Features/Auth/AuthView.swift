import SwiftUI

struct AuthView: View {
    @ObservedObject var authStore: AuthStore
    @State private var email = ""
    @State private var password = ""
    @State private var mode: AuthMode = .signIn

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header
                fields
                actions
            }
            .padding(.vertical, Spacing.xxl)
            .mlScreenPadding()
        }
        .background(Color.mlBackground)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Memory Lanes").mlKicker()
            Text(mode.title)
                .font(MLFont.displayXL)
                .foregroundStyle(Color.mlTextPrimary)
            Text("Sign in to sync your ride journal, routes, stats, and recorded GPX files.")
                .font(MLFont.body)
                .foregroundStyle(Color.mlTextSecondary)
        }
    }

    private var fields: some View {
        VStack(spacing: Spacing.md) {
            authField(title: "Email") {
                TextField("you@example.com", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            authField(title: "Password") {
                SecureField("Password", text: $password)
                    .textInputAutocapitalization(.never)
            }

            if let error = authStore.errorMessage {
                Text(error)
                    .font(MLFont.callout)
                    .foregroundStyle(Color.mlDanger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: Spacing.md) {
            PrimaryButton(title: mode.primaryTitle, systemImage: "person.crop.circle.fill", isLoading: authStore.isWorking) {
                Task {
                    switch mode {
                    case .signIn:
                        await authStore.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
                    case .signUp:
                        await authStore.signUp(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
                    }
                }
            }
            .disabled(!canSubmit)

            SecondaryButton(title: mode.secondaryTitle, systemImage: "arrow.triangle.2.circlepath") {
                authStore.errorMessage = nil
                mode = mode == .signIn ? .signUp : .signIn
            }
        }
    }

    private func authField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title).mlKicker()
            content()
                .font(MLFont.body)
                .foregroundStyle(Color.mlTextPrimary)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .frame(minHeight: 52)
                .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                        .stroke(Color.mlHairline, lineWidth: Layout.hairline)
                )
        }
    }

    private var canSubmit: Bool {
        email.contains("@") && password.count >= 6 && !authStore.isWorking
    }
}

private enum AuthMode {
    case signIn
    case signUp

    var title: String {
        switch self {
        case .signIn: "Welcome back"
        case .signUp: "Create account"
        }
    }

    var primaryTitle: String {
        switch self {
        case .signIn: "Sign In"
        case .signUp: "Create Account"
        }
    }

    var secondaryTitle: String {
        switch self {
        case .signIn: "Create a New Account"
        case .signUp: "I Already Have an Account"
        }
    }
}

#Preview {
    AuthView(authStore: AuthStore())
        .preferredColorScheme(.dark)
}
