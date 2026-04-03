import Foundation
import CoreBluetooth

/// CoreBluetooth 기반 BLE Transport (iOS 14+ / macOS 11+)
///
/// 연결 흐름:
/// 1. CBCentralManager 초기화
/// 2. "MindWave Mobile" 이름으로 스캔
/// 3. connectPeripheral → discoverServices
/// 4. ESENSE + RAW_EEG characteristic notification 활성화
/// 5. Handshake(START_ESENSE) 전송 → connect() resume
public final class BLETransport: NSObject, Transport {

    // MARK: - AsyncStream 출력

    public let dataStream: AsyncStream<BrainWaveData>
    public let stateStream: AsyncStream<ConnectionState>

    private let dataContinuation: AsyncStream<BrainWaveData>.Continuation
    private let stateContinuation: AsyncStream<ConnectionState>.Continuation

    // MARK: - 내부 상태

    // BLETransport 내부에서만 사용하는 CBUUID 인스턴스
    private let esenseUUID    = CBUUID(string: NeuroSkyUUID.esense)
    private let handshakeUUID = CBUUID(string: NeuroSkyUUID.handshake)
    private let rawEegUUID    = CBUUID(string: NeuroSkyUUID.rawEeg)

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var handshakeChar: CBCharacteristic?
    private var targetAddress: String = ""

    /// connect() 호출자를 실제 BLE 연결 완료까지 대기시키는 continuation
    private var connectContinuation: CheckedContinuation<Void, Error>?

    /// esense + rawEeg 두 notification이 모두 활성화됐는지 추적
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

    /// 실제 BLE 연결 완료(handshake 전송 완료)까지 suspend
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
        // connect() 대기 중이면 에러로 resume (미반환 시 영구 hang)
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
        // setNotifyValue가 CCCD 디스크립터를 자동으로 write함
    }

    /// esense + rawEeg 둘 다 notification 활성화된 후 연결 완료 처리
    private func resumeIfFullyConnected() {
        let required: Set<String> = [
            esenseUUID.uuidString,
            rawEegUUID.uuidString
        ]
        guard required.isSubset(of: notifiedCharacteristics),
              handshakeChar != nil else { return }

        stateContinuation.yield(.connected)
        Task { try? await sendCommand(NeuroSkyCommand.startEsense) }

        // connect() 호출자 resume
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
