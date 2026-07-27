import Foundation

enum RideMeshSignal: String, Codable, CaseIterable, Hashable, Sendable {
    case allGood = "all_good"
    case regroup
    case fuelStop = "fuel_stop"
    case assistance

    var title: String {
        switch self {
        case .allGood: "All good"
        case .regroup: "Regroup"
        case .fuelStop: "Fuel stop"
        case .assistance: "Need help"
        }
    }

    var message: String {
        switch self {
        case .allGood: "All good here."
        case .regroup: "Let's regroup when safe."
        case .fuelStop: "I need a fuel stop."
        case .assistance: "I need assistance. Please stop somewhere safe."
        }
    }

    var symbol: String {
        switch self {
        case .allGood: "checkmark.circle.fill"
        case .regroup: "person.3.fill"
        case .fuelStop: "fuelpump.fill"
        case .assistance: "exclamationmark.triangle.fill"
        }
    }
}

enum RideMeshDeliveryState: Equatable, Sendable {
    case queued
    case sharedNearby(peerCount: Int)

    var title: String {
        switch self {
        case .queued: "Waiting for a nearby rider"
        case .sharedNearby(let peerCount):
            peerCount == 1 ? "Shared with 1 nearby rider" : "Shared with \(peerCount) nearby riders"
        }
    }

    var symbol: String {
        switch self {
        case .queued: "clock"
        case .sharedNearby: "checkmark"
        }
    }
}

enum RideMeshConnectionState: Equatable, Sendable {
    case idle
    case scanning
    case connected(peerCount: Int)
    case unavailable(message: String)

    var title: String {
        switch self {
        case .idle: "Off"
        case .scanning: "Looking nearby"
        case .connected(let peerCount):
            peerCount == 1 ? "1 rider nearby" : "\(peerCount) riders nearby"
        case .unavailable: "Unavailable"
        }
    }

    var symbol: String {
        switch self {
        case .idle: "antenna.radiowaves.left.and.right.slash"
        case .scanning: "antenna.radiowaves.left.and.right"
        case .connected: "checkmark.circle.fill"
        case .unavailable: "exclamationmark.triangle.fill"
        }
    }
}

struct RideMeshMessage: Identifiable, Equatable, Sendable {
    let id: UUID
    let senderID: UUID
    let senderName: String
    let body: String
    let signal: RideMeshSignal?
    let createdAt: Date
    let isMine: Bool
    var deliveryState: RideMeshDeliveryState?
}

struct RideMeshPacket: Codable, Equatable, Sendable {
    static let currentVersion: UInt8 = 1

    let version: UInt8
    let messageID: UUID
    let channelID: String
    let createdAtMilliseconds: Int64
    let originTTL: UInt8
    var remainingTTL: UInt8
    let sealedPayload: Data
}

struct RideMeshPayload: Codable, Equatable, Sendable {
    let senderID: UUID
    let senderName: String
    let body: String
    let signal: RideMeshSignal?
}

