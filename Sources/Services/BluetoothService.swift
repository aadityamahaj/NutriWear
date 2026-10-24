import Foundation
import CoreBluetooth

/// A discovered Bluetooth peripheral surfaced to the UI.
struct BluetoothDevice: Identifiable, Equatable {
    let id: UUID
    var name: String
    var rssi: Int
    var isConnected: Bool

    static func == (lhs: BluetoothDevice, rhs: BluetoothDevice) -> Bool { lhs.id == rhs.id }
}

/// Transfers a non-Sendable CBPeripheral across the main-queue delegate →
/// main-actor boundary. Safe because the central manager delegate queue is
/// `.main`, so both sides run on the same thread.
private struct PeripheralBox: @unchecked Sendable {
    let peripheral: CBPeripheral
}

/// Scans for and connects to Bluetooth LE devices. Built so future NutriWear
/// hardware (a wearable camera/sensor) can pair over BLE; today it discovers
/// and connects to any nearby peripheral so the flow is real and demoable.
@MainActor
final class BluetoothService: NSObject, ObservableObject {

    enum State: String {
        case unknown, unsupported, unauthorized, poweredOff, ready, scanning
    }

    @Published var state: State = .unknown
    @Published var devices: [BluetoothDevice] = []
    @Published var connectedDevice: BluetoothDevice?
    @Published var statusMessage: String?

    private var central: CBCentralManager!
    /// Keep strong refs to peripherals we might connect to (CB won't retain them).
    private var peripherals: [UUID: CBPeripheral] = [:]

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    var isScanning: Bool { state == .scanning }

    func startScan() {
        guard central.state == .poweredOn else {
            statusMessage = readableState(central.state)
            return
        }
        devices.removeAll()
        peripherals.removeAll()
        state = .scanning
        statusMessage = "Scanning for nearby devices…"
        // nil services = discover everything (future device advertises its own).
        central.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
    }

    func stopScan() {
        central.stopScan()
        if state == .scanning { state = .ready }
    }

    func connect(_ device: BluetoothDevice) {
        guard let peripheral = peripherals[device.id] else { return }
        stopScan()
        statusMessage = "Connecting to \(device.name)…"
        central.connect(peripheral, options: nil)
    }

    func disconnect() {
        guard let connected = connectedDevice, let peripheral = peripherals[connected.id] else { return }
        central.cancelPeripheralConnection(peripheral)
    }

    private func readableState(_ s: CBManagerState) -> String {
        switch s {
        case .poweredOff: return "Bluetooth is off. Turn it on in Control Center or Settings."
        case .unauthorized: return "Bluetooth permission denied. Enable it in Settings."
        case .unsupported: return "This device doesn't support Bluetooth LE."
        case .resetting: return "Bluetooth is resetting…"
        default: return "Preparing Bluetooth…"
        }
    }
}

extension BluetoothService: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let s = central.state
        Task { @MainActor in
            switch s {
            case .poweredOn: self.state = .ready; self.statusMessage = "Ready to scan."
            case .poweredOff: self.state = .poweredOff
            case .unauthorized: self.state = .unauthorized
            case .unsupported: self.state = .unsupported
            default: self.state = .unknown
            }
            if s != .poweredOn { self.statusMessage = self.readableState(s) }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name
            ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? "Unknown device"
        let id = peripheral.identifier
        let rssi = RSSI.intValue
        let box = PeripheralBox(peripheral: peripheral)
        Task { @MainActor in
            self.peripherals[id] = box.peripheral
            let device = BluetoothDevice(id: id, name: name, rssi: rssi, isConnected: false)
            if let idx = self.devices.firstIndex(where: { $0.id == id }) {
                self.devices[idx] = device
            } else {
                self.devices.append(device)
            }
            self.devices.sort { $0.rssi > $1.rssi }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let id = peripheral.identifier
        let name = peripheral.name ?? "Device"
        Task { @MainActor in
            self.connectedDevice = BluetoothDevice(id: id, name: name, rssi: 0, isConnected: true)
            self.statusMessage = "Connected to \(name)."
            if let idx = self.devices.firstIndex(where: { $0.id == id }) {
                self.devices[idx].isConnected = true
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let msg = error?.localizedDescription ?? "Couldn't connect."
        Task { @MainActor in self.statusMessage = "Connection failed: \(msg)" }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let id = peripheral.identifier
        Task { @MainActor in
            if self.connectedDevice?.id == id { self.connectedDevice = nil }
            if let idx = self.devices.firstIndex(where: { $0.id == id }) {
                self.devices[idx].isConnected = false
            }
            self.statusMessage = "Disconnected."
        }
    }
}
