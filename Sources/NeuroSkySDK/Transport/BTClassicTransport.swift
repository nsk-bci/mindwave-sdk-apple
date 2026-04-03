#if os(macOS)
import Foundation
import IOBluetooth

/// IOBluetooth 기반 BT Classic SPP Transport (macOS 전용)
///
/// 연결 흐름:
/// 1. IOBluetoothDevice 조회 (주소 또는 페어링 목록)
/// 2. openRFCOMMChannelSync → 채널 획득
/// 3. InputStream에서 바이트 읽기 → ThinkGearParser
/// 4. BrainWaveData emit
public final class BTClassicTransport: NSObject, Transport {

    // MARK: - AsyncStream 출력

    public let dataStream: AsyncStream<BrainWaveData>
    public let stateStream: AsyncStream<ConnectionState>

    private let dataContinuation: AsyncStream<BrainWaveData>.Continuation
    private let stateContinuation: AsyncStream<ConnectionState>.Continuation

    // MARK: - 내부 상태

    private var device: IOBluetoothDevice?
    private var rfcommChannel: IOBluetoothRFCOMMChannel?
    private let parser = ThinkGearParser()
    private var readBuffer = Data()

    // MARK: - Init

    public override init() {
        var dataCont: AsyncStream<BrainWaveData>.Continuation!
        var stateCont: AsyncStream<ConnectionState>.Continuation!

        dataStream  = AsyncStream { dataCont  = $0 }
        stateStream = AsyncStream { stateCont = $0 }

        dataContinuation  = dataCont
        stateContinuation = stateCont

        super.init()
    }

    // MARK: - Transport

    public func connect(to deviceAddress: String) async throws {
        stateContinuation.yield(.connecting)

        // 페어링된 디바이스 목록에서 이름 또는 주소로 검색
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        let found = paired.first {
            $0.name?.lowercased().contains(deviceAddress.lowercased()) == true ||
            $0.addressString == deviceAddress
        }

        guard let btDevice = found else {
            stateContinuation.yield(.error(BTError.deviceNotFound))
            throw BTError.deviceNotFound
        }

        device = btDevice

        var channel: IOBluetoothRFCOMMChannel?
        let result = btDevice.openRFCOMMChannelSync(
            &channel,
            withChannelID: 1,  // MindWave SPP channel
            delegate: self
        )

        guard result == kIOReturnSuccess, let ch = channel else {
            stateContinuation.yield(.error(BTError.connectionFailed))
            throw BTError.connectionFailed
        }

        rfcommChannel = ch
        stateContinuation.yield(.connected)
    }

    public func disconnect() async {
        rfcommChannel?.close()
        rfcommChannel = nil
        device?.closeConnection()
        device = nil
        stateContinuation.yield(.disconnected)
    }

    public func sendCommand(_ command: UInt8) async throws {
        guard let channel = rfcommChannel else { return }
        var packet = [UInt8](ThinkGearParser.buildHandshake(command: command))
        channel.writeSync(&packet, length: UInt16(packet.count))
    }
}

// MARK: - IOBluetoothRFCOMMChannelDelegate

extension BTClassicTransport: IOBluetoothRFCOMMChannelDelegate {

    public func rfcommChannelData(
        _ rfcommChannel: IOBluetoothRFCOMMChannel!,
        data dataPointer: UnsafeMutableRawPointer!,
        length dataLength: Int
    ) {
        guard let ptr = dataPointer else { return }
        let incoming = Data(bytes: ptr, count: dataLength)
        readBuffer.append(incoming)

        // ThinkGear BT Classic 스트림: 0xAA 0xAA 동기 헤더 기반 패킷 분리
        processBuffer()
    }

    public func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        stateContinuation.yield(.disconnected)
    }

    // MARK: - 버퍼 처리

    /// BT Classic 스트림은 연속 바이트이므로 ThinkGear 동기 헤더(0xAA 0xAA)로 패킷 경계 탐색
    private func processBuffer() {
        let bytes = [UInt8](readBuffer)
        var i = 0

        while i + 3 < bytes.count {
            guard bytes[i] == 0xAA, bytes[i + 1] == 0xAA else { i += 1; continue }

            let payloadLen = Int(bytes[i + 2])
            let packetEnd  = i + 3 + payloadLen + 1  // +1 checksum

            guard packetEnd <= bytes.count else { break }

            let payload  = Array(bytes[(i + 3)..<(i + 3 + payloadLen)])
            let checksum = bytes[packetEnd - 1]

            // 체크섬 검증
            let computed = UInt8(payload.reduce(0, { ($0 + Int($1)) & 0xFF }) ^ 0xFF)
            guard computed == checksum else { i += 1; continue }

            // eSense 패킷 타입 판별 후 파싱
            parseBTPayload(payload)

            i = packetEnd
        }

        readBuffer = Data(bytes[i...])
    }

    private func parseBTPayload(_ payload: [UInt8]) {
        var j = 0
        var poorSig: Int? = nil
        var att: Int?     = nil
        var med: Int?     = nil

        while j < payload.count {
            let code = payload[j]; j += 1

            switch code {
            case 0x02:  // PoorSignal (1바이트)
                guard j < payload.count else { return }
                poorSig = Int(payload[j]); j += 1

            case 0x04:  // Attention (1바이트)
                guard j < payload.count else { return }
                att = Int(payload[j]); j += 1

            case 0x05:  // Meditation (1바이트)
                guard j < payload.count else { return }
                med = Int(payload[j]); j += 1

            case 0x80:  // Raw EEG (2바이트)
                guard j + 1 < payload.count else { return }
                let raw = Data([payload[j], payload[j + 1]]); j += 2
                dataContinuation.yield(parser.parseRawEeg(raw))

            case 0x83:  // EEG Power (24바이트 = 8 × 3바이트 big-endian)
                guard j + 23 < payload.count else { return }
                let eegBytes = Array(payload[j..<(j + 24)]); j += 24
                if let data = parser.parseEEGPowerBT(eegBytes) {
                    dataContinuation.yield(data)
                }

            default:    // 알 수 없는 코드 → 길이 바이트로 스킵
                guard j < payload.count else { return }
                let len = Int(payload[j]); j += 1 + len
            }
        }

        // eSense 값이 하나라도 수신됐으면 누적 상태에 반영 후 emit
        if poorSig != nil || att != nil || med != nil {
            dataContinuation.yield(
                parser.updateAndSnapshot(poorSignal: poorSig, attention: att, meditation: med)
            )
        }
    }
}

// MARK: - Error

public enum BTError: Error {
    case deviceNotFound
    case connectionFailed
}
#endif
