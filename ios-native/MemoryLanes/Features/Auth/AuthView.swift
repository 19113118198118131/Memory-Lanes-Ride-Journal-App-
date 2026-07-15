import SwiftUI

struct AuthView: View {
    @ObservedObject var authStore: AuthStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedField: AuthField?
    @State private var email = ""
    @State private var password = ""
    @State private var mode: AuthMode = .signIn
    @State private var presentation: AuthPresentation = .welcome
    @State private var revealsPassword = false

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                Group {
                    switch presentation {
                    case .welcome:
                        welcome(minHeight: proxy.size.height)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    case .credentials:
                        credentials(minHeight: proxy.size.height)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color.mlBackground.ignoresSafeArea())
        .animation(reduceMotion ? nil : Motion.springGentle, value: presentation)
        .animation(reduceMotion ? nil : Motion.spring, value: mode)
        .onChange(of: mode) { _, _ in authStore.errorMessage = nil }
    }

    private func welcome(minHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: Layout.welcomeBrandMarkMaxWidth)
                .mask {
                    RoundedRectangle(cornerRadius: Radius.card * 2, style: .continuous)
                        .blur(radius: Spacing.md)
                }
                .padding(.top, Spacing.lg)
                .accessibilityHidden(true)
                .mlStaggeredReveal(index: 0, distance: Spacing.lg)

            VStack(spacing: Spacing.xs) {
                Text("Memory Lanes")
                    .font(MLFont.displayXL)
                    .foregroundStyle(Color.mlTextPrimary)
                    .multilineTextAlignment(.center)

                Text("Ride. Remember. Refine.")
                    .font(MLFont.body)
                    .foregroundStyle(Color.mlTextSecondary)
            }
            .mlStaggeredReveal(index: 1)

            Spacer(minLength: Spacing.xl)

            VStack(spacing: Spacing.md) {
                PrimaryButton(title: "Create Account", systemImage: "arrow.right") {
                    showCredentials(for: .signUp)
                }

                SecondaryButton(title: "Sign In", systemImage: "person.crop.circle") {
                    showCredentials(for: .signIn)
                }
            }
            .mlStaggeredReveal(index: 2)
        }
        .padding(.vertical, Spacing.lg)
        .mlScreenPadding()
        .frame(minHeight: minHeight)
    }

    private func credentials(minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            Button {
                focusedField = nil
                authStore.errorMessage = nil
                presentation = .welcome
            } label: {
                Image(systemName: "chevron.left")
                    .font(MLFont.headline)
                    .foregroundStyle(Color.mlTextPrimary)
                    .frame(width: Layout.minTouchTarget, height: Layout.minTouchTarget)
                    .background(Color.mlSurface, in: Circle())
                    .overlay(Circle().stroke(Color.mlHairline, lineWidth: Layout.hairline))
            }
            .buttonStyle(MLPressableButtonStyle())
            .accessibilityLabel("Back")

            HStack(spacing: Spacing.md) {
                Image("BrandMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: Spacing.xxl, height: Spacing.xxl)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Memory Lanes").mlKicker()
                    Text(mode.title)
                        .font(MLFont.title)
                        .foregroundStyle(Color.mlTextPrimary)
                }
            }
            .mlStaggeredReveal(index: 0)

            MLSegmentedControl(
                items: AuthMode.allCases,
                title: { $0.segmentTitle },
                selection: $mode
            )
            .mlStaggeredReveal(index: 1)

            VStack(spacing: Spacing.md) {
                authField(
                    title: "Email",
                    symbol: "envelope",
                    isFocused: focusedField == .email
                ) {
                    TextField("you@example.com", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }
                }

                authField(
                    title: "Password",
                    symbol: "lock",
                    isFocused: focusedField == .password
                ) {
                    HStack(spacing: Spacing.xs) {
                        Group {
                            if revealsPassword {
                                TextField("At least 6 characters", text: $password)
                            } else {
                                SecureField("At least 6 characters", text: $password)
                            }
                        }
                        .textContentType(mode == .signIn ? .password : .newPassword)
                        .textInputAutocapitalization(.never)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { submit() }

                        Button {
                            revealsPassword.toggle()
                        } label: {
                            Image(systemName: revealsPassword ? "eye.slash" : "eye")
                                .foregroundStyle(Color.mlTextSecondary)
                                .mlHitTarget()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(revealsPassword ? "Hide password" : "Show password")
                    }
                }

                if let error = authStore.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(MLFont.callout)
                        .foregroundStyle(Color.mlDanger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .accessibilityElement(children: .combine)
                }
            }
            .mlStaggeredReveal(index: 2)

            PrimaryButton(
                title: mode.primaryTitle,
                systemImage: mode == .signIn ? "arrow.right" : "person.badge.plus",
                isLoading: authStore.isWorking,
                action: submit
            )
            .disabled(!canSubmit)
            .opacity(canSubmit || authStore.isWorking ? 1 : 0.45)
            .mlStaggeredReveal(index: 3)

            Spacer(minLength: Spacing.lg)
        }
        .padding(.vertical, Spacing.lg)
        .mlScreenPadding()
        .frame(minHeight: minHeight, alignment: .top)
    }

    private func authField<Content: View>(
        title: String,
        symbol: String,
        isFocused: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title).mlKicker()
            HStack(spacing: Spacing.sm) {
                Image(systemName: symbol)
                    .foregroundStyle(isFocused ? Color.mlAccent : Color.mlTextTertiary)
                    .frame(width: Spacing.lg)
                content()
                    .font(MLFont.body)
                    .foregroundStyle(Color.mlTextPrimary)
            }
            .padding(.horizontal, Spacing.md)
            .frame(minHeight: Spacing.xxl + Spacing.xs)
            .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .stroke(isFocused ? Color.mlAccent : Color.mlHairline, lineWidth: Layout.hairline)
            }
            .animation(reduceMotion ? nil : Motion.springSnappy, value: isFocused)
        }
    }

    private func showCredentials(for mode: AuthMode) {
        self.mode = mode
        presentation = .credentials
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            focusedField = .email
        }
    }

    private func submit() {
        guard canSubmit else { return }
        focusedField = nil
        Task {
            let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
            switch mode {
            case .signIn:
                await authStore.signIn(email: cleanEmail, password: password)
            case .signUp:
                await authStore.signUp(email: cleanEmail, password: password)
            }
        }
    }

    private var canSubmit: Bool {
        email.trimmingCharacters(in: .whitespacesAndNewlines).contains("@")
            && password.count >= 6
            && !authStore.isWorking
    }
}

private enum AuthPresentation {
    case welcome
    case credentials
}

private enum AuthField {
    case email
    case password
}

private enum AuthMode: CaseIterable, Hashable {
    case signIn
    case signUp

    var segmentTitle: String {
        switch self {
        case .signIn: "Sign In"
        case .signUp: "Create Account"
        }
    }

    var title: String {
        switch self {
        case .signIn: "Welcome back"
        case .signUp: "Begin your journal"
        }
    }

    var primaryTitle: String {
        switch self {
        case .signIn: "Sign In"
        case .signUp: "Create Account"
        }
    }
}

#Preview("Welcome") {
    AuthView(authStore: AuthStore())
        .preferredColorScheme(.dark)
}
