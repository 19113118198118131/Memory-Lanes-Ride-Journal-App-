import Foundation
@preconcurrency import MultipeerConnectivity

private final class RideMeshInvitationHandler: @unchecked Sendable {
    private let handler: (Bool, MCSession?) -> Void

    init(_ handler: @escaping (Bool, MCSession?) -> Void) {
        self.handler = handler
    }

    func respond(accepted: Bool, session: MCSession?) {
        handler(accepted, session)
    }
}

@MainActor
protocol RideMeshTransportDelegate: AnyObject {
    func rideMeshTransport(_ transport: any RideMeshTransporting, didReceive data: Data, from peerName: String)
    func rideMeshTransport(_ transport: any RideMeshTransporting, didUpdatePeerCount peerCount: Int)
    func rideMeshTransport(_ transport: any RideMeshTransporting, didFail message: String)
}

@MainActor
protocol RideMeshTransporting: AnyObject {
    var delegate: (any RideMeshTransportDelegate)? { get set }
    var connectedPeerCount: Int { get }

    func start(channelID: String)
    func stop()

    @discardableResult
    func send(_ data: Data, excludingPeerNamed excludedPeerName: String?) -> Int
}

@MainActor
final class NearbyRideMeshTransport: NSObject, RideMeshTransporting {
    weak var delegate: (any RideMeshTransportDelegate)?

    private static let serviceType = "ml-ridemesh"
    private let localPeer: MCPeerID
    private let session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var channelID: String?
    private var invitedPeers: Set<String> = []

    var connectedPeerCount: Int {
        session.connectedPeers.count
    }

    override init() {
        let localPeer = MCPeerID(displayName: "ML-\(UUID().uuidString.prefix(8))")
        self.localPeer = localPeer
        self.session = MCSession(
            peer: localPeer,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        super.init()
        session.delegate = self
    }

    func start(channelID: String) {
        guard self.channelID != channelID || advertiser == nil || browser == nil else {
            delegate?.rideMeshTransport(self, didUpdatePeerCount: connectedPeerCount)
            return
        }
        stopDiscovery()
        self.channelID = channelID
        invitedPeers.removeAll()

        let advertiser = MCNearbyServiceAdvertiser(
            peer: localPeer,
            discoveryInfo: ["channel": channelID, "version": "1"],
            serviceType: Self.serviceType
        )
        let browser = MCNearbyServiceBrowser(peer: localPeer, serviceType: Self.serviceType)
        advertiser.delegate = self
        browser.delegate = self
        self.advertiser = advertiser
        self.browser = browser
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
        delegate?.rideMeshTransport(self, didUpdatePeerCount: connectedPeerCount)
    }

    func stop() {
        stopDiscovery()
        session.disconnect()
        invitedPeers.removeAll()
        channelID = nil
        delegate?.rideMeshTransport(self, didUpdatePeerCount: 0)
    }

    @discardableResult
    func send(_ data: Data, excludingPeerNamed excludedPeerName: String? = nil) -> Int {
        let recipients = session.connectedPeers.filter { $0.displayName != excludedPeerName }
        guard !recipients.isEmpty else { return 0 }
        do {
            try session.send(data, toPeers: recipients, with: .reliable)
            return recipients.count
        } catch {
            delegate?.rideMeshTransport(self, didFail: error.localizedDescription)
            return 0
        }
    }

    private func stopDiscovery() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        advertiser?.delegate = nil
        browser?.delegate = nil
        advertiser = nil
        browser = nil
    }
}

extension NearbyRideMeshTransport: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        let offeredChannel = context.flatMap { String(data: $0, encoding: .utf8) }
        let invitation = RideMeshInvitationHandler(invitationHandler)
        Task { @MainActor [weak self, invitation] in
            guard let self else {
                invitation.respond(accepted: false, session: nil)
                return
            }
            let accepted = offeredChannel == channelID
            invitation.respond(accepted: accepted, session: accepted ? session : nil)
        }
    }

    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didNotStartAdvertisingPeer error: Error
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            delegate?.rideMeshTransport(self, didFail: error.localizedDescription)
        }
    }
}

extension NearbyRideMeshTransport: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        Task { @MainActor [weak self] in
            guard let self,
                  info?["channel"] == channelID,
                  !invitedPeers.contains(peerID.displayName),
                  let channelID else { return }
            invitedPeers.insert(peerID.displayName)
            browser.invitePeer(
                peerID,
                to: session,
                withContext: Data(channelID.utf8),
                timeout: 12
            )
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor [weak self] in
            self?.invitedPeers.remove(peerID.displayName)
        }
    }

    nonisolated func browser(
        _ browser: MCNearbyServiceBrowser,
        didNotStartBrowsingForPeers error: Error
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            delegate?.rideMeshTransport(self, didFail: error.localizedDescription)
        }
    }
}

extension NearbyRideMeshTransport: MCSessionDelegate {
    nonisolated func session(
        _ session: MCSession,
        peer peerID: MCPeerID,
        didChange state: MCSessionState
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if state == .notConnected {
                invitedPeers.remove(peerID.displayName)
            }
            delegate?.rideMeshTransport(self, didUpdatePeerCount: connectedPeerCount)
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            delegate?.rideMeshTransport(self, didReceive: data, from: peerID.displayName)
        }
    }

    nonisolated func session(
        _ session: MCSession,
        didReceive stream: InputStream,
        withName streamName: String,
        fromPeer peerID: MCPeerID
    ) {}

    nonisolated func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {}

    nonisolated func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {}
}
