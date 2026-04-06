#if os(macOS)
import Foundation
import IOBluetooth

/// IOBluetooth-based BT Classic SPP transport (macOS only)
///
/// Connection flow:
/// 1. Look up the device in the paired devices list by name or address
/// 2. openRFCOMMChannelSync → acquire channel
/// 3. Read bytes from the delegate callback → ThinkGearParser
/// 4. Emit BrainWaveData
public final class BTClassicTransport: NSObject, Transport {

    // MARK: - AsyncStream output

    public let dataStream: AsyncStream<BrainWaveData>
    public let stateStream: AsyncStream<ConnectionState>

    private let dataContinuation: AsyncStream<BrainWaveData>.Continuation
    private let stateContinuation: AsyncStream<ConnectionState>.Continuation

    // MARK: - Internal state

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

        // Search paired devices by name or address
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

        // BT Classic stream is continuous bytes — find packet boundaries via 0xAA 0xAA sync header
        processBuffer()
    }

    public func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        stateContinuation.yield(.disconnected)
    }

    // MARK: - Buffer processing

    private func processBuffer() {
        let bytes = [UInt8](readBuffer)
        var i = 0

        while i + 3 < bytes.count {
            guard bytes[i] == 0xAA, bytes[i + 1] == 0xAA else { i += 1; continue }

            let payloadLen = Int(bytes[i + 2])
            let packetEnd  = i + 3 + payloadLen + 1  // +1 for checksum byte

            guard packetEnd <= bytes.count else { break }

            let payload  = Array(bytes[(i + 3)..<(i + 3 + payloadLen)])
            let checksum = bytes[packetEnd - 1]

            // Validate checksum
            let computed = UInt8(payload.reduce(0, { ($0 + Int($1)) & 0xFF }) ^ 0xFF)
            guard computed == checksum else { i += 1; continue }

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
            case 0x02:  // PoorSignal (1 byte)
                guard j < payload.count else { return }
                poorSig = Int(payload[j]); j += 1

            case 0x04:  // Attention (1 byte)
                guard j < payload.count else { return }
                att = Int(payload[j]); j += 1

            case 0x05:  // Meditation (1 byte)
                guard j < payload.count else { return }
                med = Int(payload[j]); j += 1

            case 0x80:  // Raw EEG (2 bytes)
                guard j + 1 < payload.count else { return }
                let raw = Data([payload[j], payload[j + 1]]); j += 2
                dataContinuation.yield(parser.parseRawEeg(raw))

            case 0x83:  // EEG Power (24 bytes = 8 × 3-byte big-endian)
                guard j + 23 < payload.count else { return }
                let eegBytes = Array(payload[j..<(j + 24)]); j += 24
                if let data = parser.parseEEGPowerBT(eegBytes) {
                    dataContinuation.yield(data)
                }

            default:    // Unknown code — skip using length byte
                guard j < payload.count else { return }
                let len = Int(payload[j]); j += 1 + len
            }
        }

        // Emit accumulated eSense fields if any were received in this packet
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
