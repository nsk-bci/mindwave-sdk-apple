import Foundation
import CoreBluetooth

/// CoreBluetooth-based BLE transport (iOS 14+ / macOS 11+)
///
/// Connection flow:
/// 1. CBCentralManager initialization
/// 2. Scan for peripheral with matching name or UUID
/// 3. connectPeripheral → discoverServices
/// 4. Enable NOTIFY on eSense + RawEEG characteristics
/// 5. Send Handshake(START_ESENSE) → resume connect()
public final class BLETransport: NSObject, Transport {

    // MARK: - AsyncStream output

    public let dataStream: AsyncStream<BrainWaveData>
    public let stateStream: AsyncStream<ConnectionState>

    private let dataContinuation: AsyncStream<BrainWaveData>.Continuation
    private let stateContinuation: AsyncStream<ConnectionState>.Continuation

    // MARK: - Internal state

    private let esenseUUID    = CBUUID(string: NeuroSkyUUID.esense)
    private let handshakeUUID = CBUUID(string: NeuroSkyUUID.handshake)
    private let rawEegUUID    = CBUUID(string: NeuroSkyUUID.rawEeg)

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var handshakeChar: CBCharacteristic?
    private var targetAddress: String = ""

    /// Suspends the connect() caller until BLE connection is fully established.
    private var connectContinuation: CheckedContinuation<Void, Error>?

    /// Tracks which characteristics have had notifications enabled.
    /// Both eSense and RawEEG must be notifying before the connection is considered complete.
    private var notifiedCharacteristics: Set<String> = []

    private let parser = ThinkGearParser()

    // MARK: - Init

    public override init() {
        var dataCont: AsyncStream<BrainWaveData>.Continuation!
        var stateCont: AsyncStream<ConnectionState>.Continuation!

        dataStream  = AsyncStream { dataCont  = $0 }
        stateStream = AsyncStream { stateCont = $0 }

        dataContinuation  = dataCont
        stateContinuation = stateCont

        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Transport

    /// Suspend until BLE connection is fully established (handshake sent).
    public func connect(to deviceAddress: String) async throws {
        targetAddress = deviceAddress
        notifiedCharacteristics.removeAll()
        stateContinuation.yield(.scanning)

        try await withCheckedThrowingContinuation { continuation in
            self.connectContinuation = continuation
            self.central.scanForPeripherals(withServices: nil, options: nil)
        }
    }

    public func disconnect() async {
        central.stopScan()
        // Resume any pending connect() with an error to prevent a hang
        connectContinuation?.resume(throwing: CancellationError())
        connectContinuation = nil
        if let p = peripheral {
            central.cancelPeripheralConnection(p)
        }
        peripheral = nil
        stateContinuation.yield(.disconnected)
    }

    public func sendCommand(_ command: UInt8) async throws {
        guard let p = peripheral, let char = handshakeChar else { return }
        let packet = ThinkGearParser.buildHandshake(command: command)
        p.writeValue(packet, for: char, type: .withResponse)
    }

    // MARK: - Private

    private func setupNotification(for characteristic: CBCharacteristic, peripheral p: CBPeripheral) {
        p.setNotifyValue(true, for: characteristic)
        // setNotifyValue writes the CCCD descriptor automatically
    }

    /// Resume connect() once both eSense and RawEEG notifications are active.
    private func resumeIfFullyConnected() {
        let required: Set<String> = [
            esenseUUID.uuidString,
            rawEegUUID.uuidString
        ]
        guard required.isSubset(of: notifiedCharacteristics),
              handshakeChar != nil else { return }

        stateContinuation.yield(.connected)
        Task { try? await sendCommand(NeuroSkyCommand.startEsense) }

        connectContinuation?.resume()
        connectContinuation = nil
    }
}

// MARK: - CBCentralManagerDelegate

extension BLETransport: CBCentralManagerDelegate {

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn {
            let err = BLEError.bluetoothUnavailable
            stateContinuation.yield(.error(err))
            connectContinuation?.resume(throwing: err)
            connectContinuation = nil
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = peripheral.name ?? ""
        guard name.lowercased().contains(targetAddress.lowercased()) ||
              peripheral.identifier.uuidString == targetAddress else { return }

        central.stopScan()
        self.peripheral = peripheral
        stateContinuation.yield(.connecting)
        central.connect(peripheral, options: nil)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        stateContinuation.yield(.disconnected)
    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        let err = error ?? BLEError.connectionFailed
        stateContinuation.yield(.error(err))
        connectContinuation?.resume(throwing: err)
        connectContinuation = nil
    }
}

// MARK: - CBPeripheralDelegate

extension BLETransport: CBPeripheralDelegate {

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard let chars = service.characteristics else { return }
        for char in chars {
            if char.uuid == esenseUUID || char.uuid == rawEegUUID {
                setupNotification(for: char, peripheral: peripheral)
            } else if char.uuid == handshakeUUID {
                handshakeChar = char
            }
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.isNotifying else { return }
        notifiedCharacteristics.insert(characteristic.uuid.uuidString)
        resumeIfFullyConnected()
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let data = characteristic.value else { return }

        if characteristic.uuid == esenseUUID {
            if let brainData = parser.parseEsense(data) {
                dataContinuation.yield(brainData)
            }
        } else if characteristic.uuid == rawEegUUID {
            dataContinuation.yield(parser.parseRawEeg(data))
        }
    }
}

// MARK: - Error

public enum BLEError: Error {
    case bluetoothUnavailable
    case connectionFailed
    case deviceNotFound
}
