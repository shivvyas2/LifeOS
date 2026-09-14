import Foundation
import CoreBluetooth
import Integrations

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

    func prepareForSession(whoopConnected: Bool) {}
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
    }
    func connect(_ device: Device) {
        disconnect(); stopScan()
        peripheral = device.peripheral; peripheral?.delegate = self
        status = "Connecting to \(device.name)…"
        central?.connect(device.peripheral)
    }
    func disconnect() {
        stopScan()
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        peripheral = nil; connectedName = nil; bpm = nil; receivedAt = nil
        status = "No sensor connected"
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: beginScan()
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
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        connectedName = peripheral.name ?? "Heart-rate sensor"
        status = "Connected · waiting for a reading"
        peripheral.discoverServices([service])
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
