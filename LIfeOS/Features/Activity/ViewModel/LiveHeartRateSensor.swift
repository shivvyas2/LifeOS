import Foundation
import CoreBluetooth
import Integrations
import Persistence

@MainActor @Observable
final class LiveHeartRateSensor: NSObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    struct Device: Identifiable {
        let id: UUID
        let name: String
        let peripheral: CBPeripheral
    }
    private(set) var devices: [Device] = []
    private(set) var status = "No sensor connected"
    private(set) var connectedName: String?
    private(set) var scanning = false
    private(set) var bpm: Int?
    private(set) var receivedAt: Date?
    var onReading: ((Int, Date) -> Void)?
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var timeout: Task<Void, Never>?
    private let service = CBUUID(string: "180D")
    private let measurement = CBUUID(string: "2A37")
    private var wantsScan = false
    private let defaults: UserDefaults
    private static let rememberedKey = "lastHeartRateSensorID"
    private var reconnectTimeout: Task<Void, Never>?
    private var autoPairing = false
    private(set) var rememberedPeripheralID: UUID?

    init(defaults: UserDefaults = .currentAccount) {
        self.defaults = defaults
        rememberedPeripheralID = defaults.string(forKey: Self.rememberedKey).flatMap(UUID.init)
        super.init()
    }

    /// Called by the recorder at session start. Reconnects the last sensor,
    /// or looks for a lone WHOOP when the account is connected to WHOOP and
    /// nothing was ever paired here.
    func prepareForSession(whoopConnected: Bool) {
        if rememberedPeripheralID != nil { reconnectIfRemembered() }
        else if whoopConnected { autoPairWhoop() }
    }

    func reconnectIfRemembered() {
        guard let id = rememberedPeripheralID, connectedName == nil else { return }
        if central == nil { central = CBCentralManager(delegate: self, queue: .main) }
        guard let central, central.state == .poweredOn else { return }
        if let known = central.retrievePeripherals(withIdentifiers: [id]).first {
            status = "Reconnecting to \(known.name ?? "your sensor")…"
            peripheral = known; known.delegate = self
            central.connect(known)
        }
        reconnectTimeout?.cancel()
        reconnectTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, let self, self.connectedName == nil else { return }
            self.status = "Looking for your sensor…"
            self.scan()
        }
    }

    func autoPairWhoop() {
        guard connectedName == nil else { return }
        autoPairing = true
        scan()
        status = "Looking for your WHOOP…"
    }

    /// Drops the remembered sensor. An explicit disconnect means "not this
    /// one next time"; account changes clear the whole suite.
    func forget() {
        rememberedPeripheralID = nil
        defaults.removeObject(forKey: Self.rememberedKey)
    }

    func scan() {
        wantsScan = true
        if central == nil { central = CBCentralManager(delegate: self, queue: .main) }
        else { beginScan() }
    }
    private func beginScan() {
        guard central?.state == .poweredOn, wantsScan else { return }
        devices = []; scanning = true; status = "Looking for a heart-rate sensor…"
        central?.scanForPeripherals(withServices: [service])
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, let self else { return }
            self.stopScan()
            if self.connectedName == nil { self.status = "Search finished. Enable heart-rate broadcast and try again." }
        }
    }
    func stopScan() {
        wantsScan = false; scanning = false
        central?.stopScan(); timeout?.cancel(); timeout = nil
        autoPairing = false; reconnectTimeout?.cancel(); reconnectTimeout = nil
    }
    func connect(_ device: Device) {
        stopStreaming()
        peripheral = device.peripheral; peripheral?.delegate = self
        status = "Connecting to \(device.name)…"
        central?.connect(device.peripheral)
    }
    /// Ends the stream without forgetting the device.
    func stopStreaming() {
        stopScan()
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        peripheral = nil; connectedName = nil; bpm = nil; receivedAt = nil
        status = "No sensor connected"
    }
    /// Drops the remembered sensor. An explicit disconnect means "not this
    /// one next time"; account changes clear the whole suite.
    func disconnect() {
        forget()
        stopStreaming()
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if rememberedPeripheralID != nil, connectedName == nil, peripheral == nil, !wantsScan { reconnectIfRemembered() }
            beginScan()
        case .unauthorized: status = "Allow Bluetooth in Settings to use a sensor."; scanning = false
        case .poweredOff: status = "Turn on Bluetooth to connect a sensor."; scanning = false
        case .unsupported: status = "Bluetooth sensors are unavailable on this device."; scanning = false
        default: status = "Bluetooth is getting ready…"
        }
        if central.state != .poweredOn { bpm = nil; receivedAt = nil; connectedName = nil }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard !devices.contains(where: { $0.id == peripheral.identifier }) else { return }
        devices.append(Device(id: peripheral.identifier,
                              name: peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Heart-rate sensor",
                              peripheral: peripheral))
        if let id = rememberedPeripheralID, peripheral.identifier == id, self.peripheral == nil {
            connect(devices.last!); return
        }
        if autoPairing {
            switch WhoopAutoPair.choice(among: devices.map(\.name)) {
            case .one(let index): connect(devices[index])
            case .several: stopScan(); status = "More than one WHOOP nearby. Choose one under Manage."
            case .none: break
            }
        }
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        connectedName = peripheral.name ?? "Heart-rate sensor"
        status = "Connected · waiting for a reading"
        peripheral.discoverServices([service])
        reconnectTimeout?.cancel(); autoPairing = false
        rememberedPeripheralID = peripheral.identifier
        defaults.set(peripheral.identifier.uuidString, forKey: Self.rememberedKey)
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        self.peripheral = nil; status = "Could not connect. Try again."
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        self.peripheral = nil; connectedName = nil; bpm = nil; receivedAt = nil
        status = "Sensor disconnected. Reconnect to resume live heart rate."
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] { peripheral.discoverCharacteristics([measurement], for: service) }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics ?? [] where characteristic.uuid == measurement {
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard self.peripheral?.identifier == peripheral.identifier, error == nil,
              characteristic.uuid == measurement, let data = characteristic.value,
              let bpm = HeartRateMeasurement.beatsPerMinute(data) else { return }
        let date = Date.now
        self.bpm = bpm; receivedAt = date; status = "Live · \(connectedName ?? "heart-rate sensor")"
        onReading?(bpm, date)
    }
}
