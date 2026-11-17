import Foundation
import CoreBluetooth

/// Bluetooth LE link layer. Every phone advertises the Nearsend service (peripheral role) and scans for it
/// (central role), so two phones find each other without pairing. It only moves bytes: identities and packets
/// go up to `MeshRouter` (see PROTOCOL.md).
///
/// Two kinds of link, because discovery can be one-sided (e.g. an iPhone app in the background is invisible to Android scans):
/// - "out:<id>": we connected to that phone's server. We write packets to its packet characteristic and receive
///   its notifications.
/// - "in:<id>":  that phone connected to our server and subscribed to our notify characteristic. We reply by notifying it.
final class BLETransport: NSObject {
    static let service = CBUUID(string: "7A3C5E10-9D2B-4F6A-8C1E-4E4541525345")
    static let identityChar = CBUUID(string: "7A3C5E11-9D2B-4F6A-8C1E-4E4541525345")
    static let messageChar = CBUUID(string: "7A3C5E12-9D2B-4F6A-8C1E-4E4541525345")
    static let notifyChar = CBUUID(string: "7A3C5E13-9D2B-4F6A-8C1E-4E4541525345")

    /// Lets iOS relaunch the app in the background and hand back our Bluetooth state if it terminated us (e.g. low memory).
    /// Does not apply after the user force-quits the app from the app switcher.
    private static let centralRestoreID = "app.nearsend.chat.central"
    private static let peripheralRestoreID = "app.nearsend.chat.peripheral"

    private struct Identity: Codable { let id: String; let name: String; let pk: String }

    /// Our central connection to a neighbour's server ("out" link).
    private final class Link {
        let peripheral: CBPeripheral
        var messageChar: CBCharacteristic?
        var notifyChar: CBCharacteristic?
        var identityChar: CBCharacteristic?
        var identity: Identity?
        var notifyReady = false
        var announced = false
        var writes: [(Bool) -> Void] = []
        var rx = Reassembler()
        init(_ p: CBPeripheral) { peripheral = p }
    }

    /// Fragments of one packet waiting to be notified to a subscribed phone.
    private struct Outgoing { let centralID: UUID; var frags: [Data]; let done: (Bool) -> Void }

    var onNeighbor: ((_ link: String, _ id: String, _ name: String, _ pk: Data) -> Void)?
    var onLost: ((_ link: String) -> Void)?
    var onPacket: ((_ data: Data, _ link: String) -> Void)?
    var onRSSI: ((_ link: String, _ rssi: Int) -> Void)?
    var onState: ((String) -> Void)?

    private var identity: Identity
    private var central: CBCentralManager?
    private var peripheralManager: CBPeripheralManager?
    private var links: [UUID: Link] = [:]
    private var subscribers: [UUID: CBCentral] = [:]
    private var notifyCharacteristic: CBMutableCharacteristic?
    private var outgoing: [Outgoing] = []
    private var notifySeq: [UUID: UInt8] = [:]
    private var timer: Timer?
    private var rssiTick = 0

    init(id: String, name: String, publicKey: Data) {
        identity = Identity(id: id, name: name, pk: publicKey.base64EncodedString())
        super.init()
    }

    func start() {
        guard central == nil else { return }
        central = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionRestoreIdentifierKey: Self.centralRestoreID])
        peripheralManager = CBPeripheralManager(delegate: self, queue: .main, options: [CBPeripheralManagerOptionRestoreIdentifierKey: Self.peripheralRestoreID])
        // Reading signal strength keeps the radio busy: every 6 s, or every 15 s in Low Power Mode.
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.rssiTick += 1
            guard self.rssiTick % (ProcessInfo.processInfo.isLowPowerModeEnabled ? 5 : 2) == 0 else { return }
            self.links.values.forEach { if $0.peripheral.state == .connected, $0.announced { $0.peripheral.readRSSI() } }
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        central?.stopScan()
        links.values.forEach { central?.cancelPeripheralConnection($0.peripheral) }
        for (id, l) in links { l.writes.forEach { $0(false) }; if l.announced { onLost?("out:\(id.uuidString)") } }
        links.removeAll()
        for id in subscribers.keys { onLost?("in:\(id.uuidString)") }
        subscribers.removeAll(); notifySeq.removeAll()
        outgoing.forEach { $0.done(false) }; outgoing.removeAll()
        peripheralManager?.stopAdvertising()
        peripheralManager?.removeAllServices()
        central = nil; peripheralManager = nil; notifyCharacteristic = nil
    }

    func setName(_ name: String) {
        identity = Identity(id: identity.id, name: name, pk: identity.pk)
        guard let pm = peripheralManager, pm.state == .poweredOn else { return }
        pm.stopAdvertising(); pm.removeAllServices(); addService()
    }

    /// Sends one packet to a neighbour over "out:" (write) or "in:" (notify). `done(true)` once it was handed over / acknowledged.
    func write(link: String, data: Data, done: @escaping (Bool) -> Void) {
        if link.hasPrefix("out:"), let uuid = UUID(uuidString: String(link.dropFirst(4))),
           let l = links[uuid], let ch = l.messageChar, l.peripheral.state == .connected {
            l.writes.append(done)
            l.peripheral.writeValue(data, for: ch, type: .withResponse)
        } else if link.hasPrefix("in:"), let uuid = UUID(uuidString: String(link.dropFirst(3))),
                  let c = subscribers[uuid], notifyCharacteristic != nil {
            let seq = notifySeq[uuid, default: 0]; notifySeq[uuid] = seq &+ 1
            let frags = Framing.fragments(data, seq: seq, payload: max(1, c.maximumUpdateValueLength - 3))
            guard !frags.isEmpty else { done(false); return }
            outgoing.append(Outgoing(centralID: uuid, frags: frags, done: done))
            pumpNotify()
        } else {
            done(false)
        }
    }

    /// Sends queued fragments; when iOS's transmit queue is full it resumes in `peripheralManagerIsReady`.
    private func pumpNotify() {
        guard let pm = peripheralManager, let ch = notifyCharacteristic else { return }
        while !outgoing.isEmpty {
            guard let c = subscribers[outgoing[0].centralID] else { outgoing.removeFirst().done(false); continue }
            while !outgoing[0].frags.isEmpty {
                if pm.updateValue(outgoing[0].frags[0], for: ch, onSubscribedCentrals: [c]) { outgoing[0].frags.removeFirst() } else { return }
            }
            outgoing.removeFirst().done(true)
        }
    }

    private func addService() {
        let idChar = CBMutableCharacteristic(type: Self.identityChar, properties: [.read], value: try? JSONEncoder().encode(identity), permissions: [.readable])
        let msgChar = CBMutableCharacteristic(type: Self.messageChar, properties: [.write], value: nil, permissions: [.writeable])
        let nChar = CBMutableCharacteristic(type: Self.notifyChar, properties: [.notify], value: nil, permissions: [.readable])
        notifyCharacteristic = nChar
        let svc = CBMutableService(type: Self.service, primary: true)
        svc.characteristics = [idChar, msgChar, nChar]
        peripheralManager?.add(svc)
    }

    private func startScan() { central?.scanForPeripherals(withServices: [Self.service], options: nil) }

    /// A link becomes a neighbour once we have subscribed to its notifications AND read its identity.
    private func maybeAnnounce(_ p: CBPeripheral) {
        guard let l = links[p.identifier], !l.announced, l.notifyReady, let id = l.identity,
              let pk = Data(base64Encoded: id.pk), pk.count == 32, id.id != identity.id else { return }
        l.announced = true
        onNeighbor?("out:\(p.identifier.uuidString)", id.id, id.name, pk)
        p.readRSSI()
    }

    private func stateName(_ s: CBManagerState) -> String {
        switch s {
        case .poweredOn: "ready"
        case .poweredOff: "off"
        case .unauthorized: "unauthorized"
        case .unsupported: "unsupported"
        default: "starting"
        }
    }
}

extension BLETransport: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        onState?(stateName(c.state))
        if c.state == .poweredOn { startScan() }
    }

    /// Called first after a background relaunch: re-adopt the connections iOS kept alive for us and re-read their identities.
    func centralManager(_ c: CBCentralManager, willRestoreState dict: [String: Any]) {
        let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        for p in restored where links[p.identifier] == nil {
            links[p.identifier] = Link(p)
            p.delegate = self
            switch p.state {
            case .connected: p.discoverServices([Self.service])
            case .disconnected: c.connect(p)
            default: break      // still connecting; iOS will report the result
            }
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard links[p.identifier] == nil else { return }
        links[p.identifier] = Link(p)
        p.delegate = self
        c.connect(p)
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) { p.discoverServices([Self.service]) }
    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) { drop(p) }
    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) { drop(p) }

    private func drop(_ p: CBPeripheral) {
        guard let l = links.removeValue(forKey: p.identifier) else { return }
        l.writes.forEach { $0(false) }
        if l.announced { onLost?("out:\(p.identifier.uuidString)") }
        // Re-report the phone if it comes back into range.
        central?.stopScan(); startScan()
    }
}

extension BLETransport: CBPeripheralDelegate {
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let svc = p.services?.first(where: { $0.uuid == Self.service }) else { return }
        p.discoverCharacteristics([Self.identityChar, Self.messageChar, Self.notifyChar], for: svc)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let link = links[p.identifier] else { return }
        for ch in service.characteristics ?? [] {
            if ch.uuid == Self.messageChar { link.messageChar = ch }
            if ch.uuid == Self.notifyChar { link.notifyChar = ch }
            if ch.uuid == Self.identityChar { link.identityChar = ch }
        }
        if let n = link.notifyChar { p.setNotifyValue(true, for: n) } else { link.notifyReady = true }   // older peers have no notify characteristic
        if let ic = link.identityChar { p.readValue(for: ic) }
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?) {
        guard let link = links[p.identifier] else { return }
        link.notifyReady = true
        maybeAnnounce(p)
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard let link = links[p.identifier], let data = ch.value else { return }
        if ch.uuid == Self.identityChar {
            link.identity = try? JSONDecoder().decode(Identity.self, from: data)
            maybeAnnounce(p)
        } else if ch.uuid == Self.notifyChar, let packet = link.rx.add(data) {
            onPacket?(packet, "out:\(p.identifier.uuidString)")
        }
    }

    func peripheral(_ p: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard error == nil, links[p.identifier]?.announced == true else { return }
        onRSSI?("out:\(p.identifier.uuidString)", RSSI.intValue)
    }

    func peripheral(_ p: CBPeripheral, didWriteValueFor ch: CBCharacteristic, error: Error?) {
        guard let link = links[p.identifier], !link.writes.isEmpty else { return }
        link.writes.removeFirst()(error == nil)
    }
}

extension BLETransport: CBPeripheralManagerDelegate {
    /// iOS may hand back the service we had published before termination. We always rebuild it (below) so the identity
    /// it serves matches the current nickname and we never publish the service twice.
    func peripheralManager(_ pm: CBPeripheralManager, willRestoreState dict: [String: Any]) {}

    func peripheralManagerDidUpdateState(_ pm: CBPeripheralManager) {
        guard pm.state == .poweredOn else { return }
        pm.stopAdvertising(); pm.removeAllServices()
        addService()
    }

    func peripheralManager(_ pm: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        guard error == nil else { return }
        pm.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [Self.service]])
    }

    func peripheralManager(_ pm: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        if characteristic.uuid == Self.notifyChar { subscribers[central.identifier] = central }
    }

    func peripheralManager(_ pm: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        guard characteristic.uuid == Self.notifyChar, subscribers.removeValue(forKey: central.identifier) != nil else { return }
        notifySeq.removeValue(forKey: central.identifier)
        onLost?("in:\(central.identifier.uuidString)")
        pumpNotify()
    }

    func peripheralManagerIsReady(toUpdateSubscribers pm: CBPeripheralManager) { pumpNotify() }

    func peripheralManager(_ pm: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for r in requests where r.characteristic.uuid == Self.messageChar {
            if let data = r.value { onPacket?(data, "in:\(r.central.identifier.uuidString)") }
        }
        if let first = requests.first { pm.respond(to: first, withResult: .success) }
    }
}
