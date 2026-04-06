import Foundation

/// NeuroSky ThinkGear BLE packet parser
///
/// 0xEA — Attention / Meditation / PoorSignal
/// 0xEB — EEG frequency powers 1/2 (Delta, Theta, LowAlpha, HighAlpha)
/// 0xEC — EEG frequency powers 2/2 (LowBeta, HighBeta, LowGamma, MidGamma)
/// RawEEG (039afff4) — 20 bytes, 10 signed samples at 2 bytes each
public final class ThinkGearParser {

    // MARK: - Accumulated state
    // Fields are updated incrementally as packets arrive from different characteristics.

    private var poorSignal: Int = 0
    private var attention: Int = 0
    private var meditation: Int = 0
    private var delta: Int = 0
    private var theta: Int = 0
    private var lowAlpha: Int = 0
    private var highAlpha: Int = 0
    private var lowBeta: Int = 0
    private var highBeta: Int = 0
    private var lowGamma: Int = 0
    private var midGamma: Int = 0

    public init() {}

    // MARK: - eSense packet parsing (0xEA / 0xEB / 0xEC)

    /// Parse data received from the eSense characteristic (039afff8).
    /// - Returns: Updated `BrainWaveData` snapshot, or `nil` for unknown packet types.
    public func parseEsense(_ data: Data) -> BrainWaveData? {
        let bytes = [UInt8](data)
        guard !bytes.isEmpty else { return nil }

        switch bytes[0] {
        case 0xEA: return parseEA(bytes)
        case 0xEB: return parseEB(bytes)
        case 0xEC: return parseEC(bytes)
        default:   return nil
        }
    }

    /// Parse data received from the RawEEG characteristic (039afff4).
    /// - Returns: `BrainWaveData` with the `rawEeg` field populated (10 signed int samples).
    public func parseRawEeg(_ data: Data) -> BrainWaveData {
        let bytes = [UInt8](data)
        var samples: [Int] = []

        let count = bytes.count / 2
        for i in 0..<count {
            var value = (Int(bytes[i * 2]) << 8) | Int(bytes[i * 2 + 1])
            if value > 32768 { value -= 65536 }  // sign correction
            samples.append(value)
        }

        return makeSnapshot(rawEeg: samples)
    }

    // MARK: - Handshake packet builder

    /// Build the 20-byte handshake packet for the given command byte.
    public static func buildHandshake(command: UInt8) -> Data {
        var bytes = [UInt8](repeating: 0x00, count: 20)
        bytes[0] = 0x77  // header
        bytes[1] = 0x01  // length
        bytes[2] = command

        // Checksum: (bytes[1] + ... + bytes[18]) XOR 0xFF AND 0xFF
        let sum = bytes[1..<19].reduce(0, { $0 + Int($1) })
        bytes[19] = UInt8((sum ^ 0xFF) & 0xFF)

        return Data(bytes)
    }

    // MARK: - BT Classic helpers

    /// Selectively update eSense fields and return a snapshot.
    /// Parameters that are `nil` retain their last accumulated value.
    public func updateAndSnapshot(poorSignal: Int? = nil, attention: Int? = nil, meditation: Int? = nil) -> BrainWaveData {
        if let v = poorSignal  { self.poorSignal  = v }
        if let v = attention   { self.attention   = v }
        if let v = meditation  { self.meditation  = v }
        return makeSnapshot()
    }

    /// Parse a BT Classic 0x83 EEG Power TLV payload (24 bytes = 8 × 3-byte big-endian).
    public func parseEEGPowerBT(_ bytes: [UInt8]) -> BrainWaveData? {
        guard bytes.count >= 24 else { return nil }
        delta     = int24(bytes, offset: 0)
        theta     = int24(bytes, offset: 3)
        lowAlpha  = int24(bytes, offset: 6)
        highAlpha = int24(bytes, offset: 9)
        lowBeta   = int24(bytes, offset: 12)
        highBeta  = int24(bytes, offset: 15)
        lowGamma  = int24(bytes, offset: 18)
        midGamma  = int24(bytes, offset: 21)
        return makeSnapshot()
    }

    // MARK: - Private

    private func parseEA(_ bytes: [UInt8]) -> BrainWaveData? {
        guard bytes.count > 10 else { return nil }
        poorSignal = Int(bytes[6])
        attention  = Int(bytes[8])
        meditation = Int(bytes[10])
        return makeSnapshot()
    }

    private func parseEB(_ bytes: [UInt8]) -> BrainWaveData? {
        guard bytes.count > 19 else { return nil }
        delta     = int24(bytes, offset: 5)
        theta     = int24(bytes, offset: 9)
        lowAlpha  = int24(bytes, offset: 13)
        highAlpha = int24(bytes, offset: 17)
        return makeSnapshot()
    }

    private func parseEC(_ bytes: [UInt8]) -> BrainWaveData? {
        guard bytes.count > 19 else { return nil }
        lowBeta  = int24(bytes, offset: 5)
        highBeta = int24(bytes, offset: 9)
        lowGamma = int24(bytes, offset: 13)
        midGamma = int24(bytes, offset: 17)
        return makeSnapshot()
    }

    private func int24(_ bytes: [UInt8], offset: Int) -> Int {
        (Int(bytes[offset]) << 16) | (Int(bytes[offset + 1]) << 8) | Int(bytes[offset + 2])
    }

    private func makeSnapshot(rawEeg: [Int] = []) -> BrainWaveData {
        BrainWaveData(
            poorSignal: poorSignal,
            attention:  attention,
            meditation: meditation,
            delta:      delta,
            theta:      theta,
            lowAlpha:   lowAlpha,
            highAlpha:  highAlpha,
            lowBeta:    lowBeta,
            highBeta:   highBeta,
            lowGamma:   lowGamma,
            midGamma:   midGamma,
            rawEeg:     rawEeg
        )
    }
}
