import SwiftUI

struct RideMeshView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var session: RideMeshSession
    @State private var showsPrivacyDetail = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Spacing.md) {
                        connectionCard
                        quickSignals

                        if session.messages.isEmpty {
                            emptyState
                        } else {
                            ForEach(session.messages) { message in
                                messageRow(message)
                                    .id(message.id)
                            }
                        }

                        if let errorMessage = session.errorMessage {
                            errorCard(errorMessage)
                        }
                    }
                    .padding(.vertical, Spacing.md)
                    .mlScreenPadding()
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: session.messages.count) { _, _ in
                    guard let lastID = session.messages.last?.id else { return }
                    withAnimation(reduceMotion ? nil : Motion.springGentle) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                composer
            }
            .background(Color.mlBackground)
            .navigationTitle("Ride Mesh")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsPrivacyDetail = true
                    } label: {
                        Image(systemName: "info.circle")
                            .mlHitTarget()
                    }
                    .buttonStyle(MLPressableButtonStyle())
                    .accessibilityLabel("About Ride Mesh")
                }
            }
        }
        .task { session.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                session.start()
            } else {
                session.stop()
            }
        }
        .onDisappear {
            session.stop()
        }
        .sheet(isPresented: $showsPrivacyDetail) {
            RideMeshPrivacyView()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private var connectionCard: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: session.state.symbol)
                .font(MLFont.title2)
                .foregroundStyle(connectionTint)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: Layout.minTouchTarget, height: Layout.minTouchTarget)
                .background(connectionTint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(session.state.title)
                    .font(MLFont.headline)
                    .foregroundStyle(Color.mlTextPrimary)
                    .contentTransition(.numericText())
                Text(connectionDetail)
                    .font(MLFont.caption)
                    .foregroundStyle(Color.mlTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Spacing.xs)

            if case .unavailable = session.state {
                Button("Retry") {
                    session.retry()
                }
                .font(MLFont.callout)
                .foregroundStyle(Color.mlAccent)
                .frame(minHeight: Layout.minTouchTarget)
                .buttonStyle(MLPressableButtonStyle())
            }
        }
        .padding(Spacing.md)
        .background(Color.mlSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(connectionTint.opacity(0.28), lineWidth: Layout.hairline)
        }
        .animation(reduceMotion ? nil : Motion.springSnappy, value: session.state)
    }

    private var quickSignals: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Quick signals").mlKicker()
            ScrollView(.horizontal) {
                HStack(spacing: Spacing.sm) {
                    ForEach(RideMeshSignal.allCases, id: \.self) { signal in
                        Button {
                            session.send(signal: signal)
                        } label: {
                            Label(signal.title, systemImage: signal.symbol)
                                .font(MLFont.callout)
                                .foregroundStyle(signalTint(signal))
                                .padding(.horizontal, Spacing.md)
                                .frame(minHeight: Layout.minTouchTarget)
                                .background(
                                    signalTint(signal).opacity(0.12),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(MLPressableButtonStyle())
                        .disabled(!session.isActive)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(MLFont.display)
                .foregroundStyle(Color.mlAccent)
                .frame(width: Layout.emptyStateIconSize, height: Layout.emptyStateIconSize)
                .background(Color.mlAccent.opacity(0.10), in: Circle())
                .accessibilityHidden(true)

            VStack(spacing: Spacing.xs) {
                Text("The ride channel is quiet")
                    .font(MLFont.title2)
                    .foregroundStyle(Color.mlTextPrimary)
                    .multilineTextAlignment(.center)
                Text("Messages wait in this Ride Mesh session until another member of this group ride is nearby.")
                    .font(MLFont.callout)
                    .foregroundStyle(Color.mlTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xxl)
        .accessibilityElement(children: .combine)
    }

    private func messageRow(_ message: RideMeshMessage) -> some View {
        HStack {
            if message.isMine { Spacer(minLength: Spacing.xxl) }

            VStack(alignment: message.isMine ? .trailing : .leading, spacing: Spacing.xxs) {
                if !message.isMine {
                    Text(message.senderName)
                        .font(MLFont.caption)
                        .foregroundStyle(Color.mlAccent)
                }

                HStack(alignment: .top, spacing: Spacing.xs) {
                    if let signal = message.signal {
                        Image(systemName: signal.symbol)
                            .font(MLFont.callout)
                            .foregroundStyle(signalTint(signal))
                            .accessibilityHidden(true)
                    }
                    Text(message.body)
                        .font(MLFont.body)
                        .foregroundStyle(message.isMine ? Color.mlOnAccent : Color.mlTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(
                    message.isMine ? Color.mlAccent : Color.mlSurfaceElevated,
                    in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                )

                HStack(spacing: Spacing.xxs) {
                    Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                    if let deliveryState = message.deliveryState {
                        Image(systemName: deliveryState.symbol)
                        Text(deliveryState.title)
                    }
                }
                .font(MLFont.caption)
                .foregroundStyle(Color.mlTextTertiary)
                .accessibilityElement(children: .combine)
            }

            if !message.isMine { Spacer(minLength: Spacing.xxl) }
        }
        .frame(maxWidth: .infinity)
        .transition(.move(edge: message.isMine ? .trailing : .leading).combined(with: .opacity))
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: Spacing.sm) {
            TextField("Message nearby riders", text: $session.draft, axis: .vertical)
                .font(MLFont.body)
                .foregroundStyle(Color.mlTextPrimary)
                .lineLimit(1...4)
                .submitLabel(.send)
                .onSubmit {
                    if session.canSend {
                        session.sendDraft()
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .frame(minHeight: Layout.minTouchTarget)
                .background(
                    Color.mlSurfaceElevated,
                    in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                        .stroke(
                            session.draft.count > RideMeshCodec.maximumMessageLength
                                ? Color.mlDanger
                                : Color.mlHairline,
                            lineWidth: Layout.hairline
                        )
                }

            Button {
                session.sendDraft()
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(MLFont.headline)
                    .foregroundStyle(Color.mlOnAccent)
                    .frame(width: Layout.minTouchTarget, height: Layout.minTouchTarget)
                    .background(Color.mlAccent, in: Circle())
            }
            .buttonStyle(MLPressableButtonStyle())
            .disabled(!session.canSend)
            .opacity(session.canSend ? 1 : 0.45)
            .accessibilityLabel("Send nearby message")
        }
        .padding(.horizontal, Spacing.screenH)
        .padding(.vertical, Spacing.sm)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.mlHairline)
                .frame(height: Layout.hairline)
        }
    }

    private func errorCard(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(MLFont.callout)
            .foregroundStyle(Color.mlDanger)
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.mlDanger.opacity(0.10), in: RoundedRectangle(cornerRadius: Radius.card))
    }

    private var connectionTint: Color {
        switch session.state {
        case .idle: .mlTextTertiary
        case .scanning: .mlWarning
        case .connected: .mlSuccess
        case .unavailable: .mlDanger
        }
    }

    private var connectionDetail: String {
        switch session.state {
        case .idle: "Nearby messaging is off."
        case .scanning: "Keep Ride Mesh open while finding group members."
        case .connected: "Encrypted messages can hop through nearby group members."
        case .unavailable: "Check Local Network access in Settings, then retry."
        }
    }

    private func signalTint(_ signal: RideMeshSignal) -> Color {
        signal == .assistance ? .mlDanger : .mlAccent
    }
}

private struct RideMeshPrivacyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    Text("Nearby, private by design")
                        .font(MLFont.title)
                        .foregroundStyle(Color.mlTextPrimary)

                    privacyRow(
                        symbol: "wifi.slash",
                        title: "No mobile data required",
                        detail: "Ride Mesh uses direct nearby links between iPhones."
                    )
                    privacyRow(
                        symbol: "lock.fill",
                        title: "Private to this group ride",
                        detail: "The invitation token derives the channel key. Other nearby apps cannot read the messages."
                    )
                    privacyRow(
                        symbol: "arrow.triangle.branch",
                        title: "Riders can relay",
                        detail: "A message may hop across nearby members, with strict expiry and duplicate protection."
                    )
                    privacyRow(
                        symbol: "exclamationmark.shield",
                        title: "Not an emergency service",
                        detail: "Nearby delivery is not guaranteed. Call emergency services whenever it is safe and possible."
                    )
                }
                .padding(.vertical, Spacing.lg)
                .mlScreenPadding()
            }
            .background(Color.mlBackground)
            .navigationTitle("About Ride Mesh")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func privacyRow(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: symbol)
                .font(MLFont.headline)
                .foregroundStyle(Color.mlAccent)
                .frame(width: Layout.minTouchTarget, height: Layout.minTouchTarget)
                .background(Color.mlAccent.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(MLFont.headline)
                    .foregroundStyle(Color.mlTextPrimary)
                Text(detail)
                    .font(MLFont.callout)
                    .foregroundStyle(Color.mlTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    RideMeshView(
        session: RideMeshSession(
            shareToken: UUID(),
            senderName: "Samar"
        )
    )
    .preferredColorScheme(.dark)
}
