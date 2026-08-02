import Foundation
@preconcurrency import CoreBluetooth

@MainActor
final class BluetoothRideMeshTransport: NSObject, RideMeshTransporting {
    weak var delegate: (any RideMeshTransportDelegate)?

    private struct Handshake: Codable {
        let channelID: String
        let nodeID: UUID
    }

    private struct PeripheralLink {
        let peripheral: CBPeripheral
        let characteristic: CBCharacteristic
        var nodeID: UUID?
    }

    private struct CentralLink {
        let central: CBCentral
        var nodeID: UUID?
    }

    private enum Endpoint {
        case peripheral(UUID)
        case central(UUID)

        var assemblyKey: String {
            switch self {
            case .peripheral(let id): "peripheral:\(id.uuidString)"
            case .central(let id): "central:\(id.uuidString)"
            }
        }
    }

    private static let serviceUUID = CBUUID(string: "B7A1C000-6D5A-4A8C-9F12-4D454D4C0001")
    private static let characteristicUUID = CBUUID(string: "B7A1C001-6D5A-4A8C-9F12-4D454D4C0001")
    private static let maximumBLEFrameByteCount = 512
    private static let maximumQueuedFrameCount = 1_024

    private let nodeID: UUID
    private var centralManager: CBCentralManager?
    private var peripheralManager: CBPeripheralManager?
    private var mutableCharacteristic: CBMutableCharacteristic?
    private var channelID: String?
    private var isStarted = false
    private var isAdvertising = false
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    private var peripheralLinks: [UUID: PeripheralLink] = [:]
    private var centralLinks: [UUID: CentralLink] = [:]
    private var pendingWrites: [UUID: [Data]] = [:]
    private var pendingNotifications: [(Data, UUID)] = []
    private var reassembler = RideMeshBLEReassembler()
    private var lastReportedPeerCount = -1

    var connectedPeerCount: Int {
        let identified = Set(
            peripheralLinks.values.compactMap(\.nodeID)
                + centralLinks.values.compactMap(\.nodeID)
        )
        if !identified.isEmpty { return identified.count }
        return max(peripheralLinks.count, centralLinks.count)
    }

    override init() {
        let defaultsKey = "memory-lanes.ride-mesh.ble-node-id"
        if let stored = UserDefaults.standard.string(forKey: defaultsKey),
           let id = UUID(uuidString: stored) {
            nodeID = id
        } else {
            let id = UUID()
            nodeID = id
            UserDefaults.standard.set(id.uuidString, forKey: defaultsKey)
        }
        super.init()
    }

    func start(channelID: String) {
        if isStarted, self.channelID == channelID {
            reportPeerCount()
            return
        }
        stop()
        self.channelID = channelID
        isStarted = true
        centralManager = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )
        peripheralManager = CBPeripheralManager(
            delegate: self,
            queue: nil,
            options: [CBPeripheralManagerOptionShowPowerAlertKey: false]
        )
        reportPeerCount()
    }

    func stop() {
        isStarted = false
        centralManager?.stopScan()
        for peripheral in discoveredPeripherals.values {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        peripheralManager?.stopAdvertising()
        peripheralManager?.removeAllServices()
        centralManager?.delegate = nil
        peripheralManager?.delegate = nil
        centralManager = nil
        peripheralManager = nil
        mutableCharacteristic = nil
        channelID = nil
        isAdvertising = false
        discoveredPeripherals.removeAll()
        peripheralLinks.removeAll()
        centralLinks.removeAll()
        pendingWrites.removeAll()
        pendingNotifications.removeAll()
        reassembler = RideMeshBLEReassembler()
        reportPeerCount(force: true)
    }

    @discardableResult
    func send(_ data: Data, excludingPeerNamed excludedPeerName: String?) -> Int {
        guard isStarted else { return 0 }
        var recipients: Set<UUID> = []

        for link in peripheralLinks.values {
            guard let remoteNodeID = link.nodeID,
                  peerName(for: remoteNodeID) != excludedPeerName else { continue }
            send(
                data,
                kind: .packet,
                to: link.peripheral,
                characteristic: link.characteristic
            )
            recipients.insert(remoteNodeID)
        }

        guard let characteristic = mutableCharacteristic else { return recipients.count }
        for link in centralLinks.values {
            guard let remoteNodeID = link.nodeID,
                  peerName(for: remoteNodeID) != excludedPeerName else { continue }
            send(data, kind: .packet, to: link.central, characteristic: characteristic)
            recipients.insert(remoteNodeID)
        }
        return recipients.count
    }

    private func configureCentralIfReady() {
        guard isStarted, centralManager?.state == .poweredOn else { return }
        centralManager?.stopScan()
        centralManager?.scanForPeripherals(
            withServices: [Self.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    private func configurePeripheralIfReady() {
        guard isStarted,
              peripheralManager?.state == .poweredOn,
              mutableCharacteristic == nil else { return }
        let characteristic = CBMutableCharacteristic(
            type: Self.characteristicUUID,
            properties: [.notify, .write, .writeWithoutResponse],
            value: nil,
            permissions: [.writeable]
        )
        let service = CBMutableService(type: Self.serviceUUID, primary: true)
        service.characteristics = [characteristic]
        mutableCharacteristic = characteristic
        peripheralManager?.add(service)
    }

    private func sendHandshake(to peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        guard let handshake = handshakeData else { return }
        send(handshake, kind: .handshake, to: peripheral, characteristic: characteristic)
    }

    private func sendHandshake(to central: CBCentral, characteristic: CBMutableCharacteristic) {
        guard let handshake = handshakeData else { return }
        send(handshake, kind: .handshake, to: central, characteristic: characteristic)
    }

    private var handshakeData: Data? {
        guard let channelID else { return nil }
        return try? JSONEncoder().encode(Handshake(channelID: channelID, nodeID: nodeID))
    }

    private func send(
        _ data: Data,
        kind: RideMeshBLEFrameKind,
        to peripheral: CBPeripheral,
        characteristic: CBCharacteristic
    ) {
        let limit = min(
            max(peripheral.maximumWriteValueLength(for: .withoutResponse), RideMeshBLEFrame.headerByteCount + 1),
            Self.maximumBLEFrameByteCount
        )
        let fragments = RideMeshBLEFrame.fragments(
            for: data,
            kind: kind,
            maximumFrameByteCount: limit
        )
        for fragment in fragments {
            if peripheral.canSendWriteWithoutResponse,
               pendingWrites[peripheral.identifier, default: []].isEmpty {
                peripheral.writeValue(fragment, for: characteristic, type: .withoutResponse)
            } else {
                enqueueWrite(fragment, for: peripheral.identifier)
            }
        }
    }

    private func send(
        _ data: Data,
        kind: RideMeshBLEFrameKind,
        to central: CBCentral,
        characteristic: CBMutableCharacteristic
    ) {
        let limit = min(
            max(central.maximumUpdateValueLength, RideMeshBLEFrame.headerByteCount + 1),
            Self.maximumBLEFrameByteCount
        )
        for fragment in RideMeshBLEFrame.fragments(
            for: data,
            kind: kind,
            maximumFrameByteCount: limit
        ) {
            let sent = peripheralManager?.updateValue(
                fragment,
                for: characteristic,
                onSubscribedCentrals: [central]
            ) ?? false
            if !sent {
                enqueueNotification(fragment, for: central.identifier)
            }
        }
    }

    private func enqueueWrite(_ data: Data, for peripheralID: UUID) {
        var queue = pendingWrites[peripheralID, default: []]
        if queue.count >= Self.maximumQueuedFrameCount {
            queue.removeFirst(queue.count - Self.maximumQueuedFrameCount + 1)
        }
        queue.append(data)
        pendingWrites[peripheralID] = queue
    }

    private func enqueueNotification(_ data: Data, for centralID: UUID) {
        if pendingNotifications.count >= Self.maximumQueuedFrameCount {
            pendingNotifications.removeFirst(
                pendingNotifications.count - Self.maximumQueuedFrameCount + 1
            )
        }
        pendingNotifications.append((data, centralID))
    }

    private func drainWrites(for peripheral: CBPeripheral) {
        guard let characteristic = peripheralLinks[peripheral.identifier]?.characteristic else { return }
        var queue = pendingWrites[peripheral.identifier, default: []]
        while peripheral.canSendWriteWithoutResponse, !queue.isEmpty {
            peripheral.writeValue(queue.removeFirst(), for: characteristic, type: .withoutResponse)
        }
        pendingWrites[peripheral.identifier] = queue
    }

    private func drainNotifications() {
        guard let characteristic = mutableCharacteristic,
              let peripheralManager else { return }
        while let first = pendingNotifications.first,
              let central = centralLinks[first.1]?.central {
            guard peripheralManager.updateValue(
                first.0,
                for: characteristic,
                onSubscribedCentrals: [central]
            ) else { return }
            pendingNotifications.removeFirst()
        }
        pendingNotifications.removeAll { centralLinks[$0.1] == nil }
    }

    private func receive(_ data: Data, from endpoint: Endpoint) {
        guard let assembly = reassembler.ingest(data, from: endpoint.assemblyKey) else { return }
        switch assembly.kind {
        case .handshake:
            acceptHandshake(assembly.data, from: endpoint)
        case .packet:
            guard let remoteNodeID = remoteNodeID(for: endpoint) else { return }
            delegate?.rideMeshTransport(
                self,
                didReceive: assembly.data,
                from: peerName(for: remoteNodeID)
            )
        }
    }

    private func acceptHandshake(_ data: Data, from endpoint: Endpoint) {
        guard let handshake = try? JSONDecoder().decode(Handshake.self, from: data),
              handshake.channelID == channelID,
              handshake.nodeID != nodeID else { return }
        switch endpoint {
        case .peripheral(let id):
            peripheralLinks[id]?.nodeID = handshake.nodeID
        case .central(let id):
            centralLinks[id]?.nodeID = handshake.nodeID
        }
        reportPeerCount()
    }

    private func remoteNodeID(for endpoint: Endpoint) -> UUID? {
        switch endpoint {
        case .peripheral(let id): peripheralLinks[id]?.nodeID
        case .central(let id): centralLinks[id]?.nodeID
        }
    }

    private func peerName(for nodeID: UUID) -> String {
        "ble:\(nodeID.uuidString.lowercased())"
    }

    private func reportPeerCount(force: Bool = false) {
        let count = isStarted ? connectedPeerCount : 0
        guard force || count != lastReportedPeerCount else { return }
        lastReportedPeerCount = count
        delegate?.rideMeshTransport(self, didUpdatePeerCount: count)
    }

    private func reportUnavailable(_ message: String) {
        delegate?.rideMeshTransport(self, didFail: message)
    }
}

extension BluetoothRideMeshTransport: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            configureCentralIfReady()
        case .unauthorized:
            reportUnavailable("Bluetooth access is off for Memory Lanes. Enable it in Settings to use offline Ride Mesh.")
        case .unsupported:
            reportUnavailable("This device does not support Bluetooth Ride Mesh.")
        case .poweredOff:
            reportPeerCount(force: true)
        default:
            break
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard isStarted,
              discoveredPeripherals[peripheral.identifier] == nil else { return }
        discoveredPeripherals[peripheral.identifier] = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        discoveredPeripherals.removeValue(forKey: peripheral.identifier)
        peripheralLinks.removeValue(forKey: peripheral.identifier)
        pendingWrites.removeValue(forKey: peripheral.identifier)
        reportPeerCount()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        timestamp: CFAbsoluteTime,
        isReconnecting: Bool,
        error: Error?
    ) {
        discoveredPeripherals.removeValue(forKey: peripheral.identifier)
        peripheralLinks.removeValue(forKey: peripheral.identifier)
        pendingWrites.removeValue(forKey: peripheral.identifier)
        reportPeerCount()
    }
}

extension BluetoothRideMeshTransport: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil,
              let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            centralManager?.cancelPeripheralConnection(peripheral)
            return
        }
        peripheral.discoverCharacteristics([Self.characteristicUUID], for: service)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil,
              let characteristic = service.characteristics?.first(where: {
                  $0.uuid == Self.characteristicUUID
              }) else {
            centralManager?.cancelPeripheralConnection(peripheral)
            return
        }
        peripheralLinks[peripheral.identifier] = PeripheralLink(
            peripheral: peripheral,
            characteristic: characteristic,
            nodeID: nil
        )
        peripheral.setNotifyValue(true, for: characteristic)
        sendHandshake(to: peripheral, characteristic: characteristic)
        reportPeerCount()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil, let value = characteristic.value else { return }
        receive(value, from: .peripheral(peripheral.identifier))
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        drainWrites(for: peripheral)
    }
}

extension BluetoothRideMeshTransport: @preconcurrency CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            configurePeripheralIfReady()
        case .unauthorized:
            reportUnavailable("Bluetooth access is off for Memory Lanes. Enable it in Settings to use offline Ride Mesh.")
        case .unsupported:
            reportUnavailable("This device does not support Bluetooth Ride Mesh.")
        case .poweredOff:
            reportPeerCount(force: true)
        default:
            break
        }
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didAdd service: CBService,
        error: Error?
    ) {
        guard error == nil, isStarted else {
            if let error { reportUnavailable(error.localizedDescription) }
            return
        }
        peripheral.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID]])
        isAdvertising = true
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic
    ) {
        centralLinks[central.identifier] = CentralLink(central: central, nodeID: nil)
        if let characteristic = characteristic as? CBMutableCharacteristic {
            sendHandshake(to: central, characteristic: characteristic)
        }
        reportPeerCount()
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didUnsubscribeFrom characteristic: CBCharacteristic
    ) {
        centralLinks.removeValue(forKey: central.identifier)
        pendingNotifications.removeAll { $0.1 == central.identifier }
        reportPeerCount()
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didReceiveWrite requests: [CBATTRequest]
    ) {
        for request in requests {
            if let value = request.value {
                receive(value, from: .central(request.central.identifier))
                peripheral.respond(to: request, withResult: .success)
            } else {
                peripheral.respond(to: request, withResult: .invalidAttributeValueLength)
            }
        }
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        drainNotifications()
    }
}
