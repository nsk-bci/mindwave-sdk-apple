import Foundation

/// NeuroSky ThinkGear BLE packet parser
///
/// 0xEA — Attention / Meditation / PoorSignal
/// 0xEB — EEG frequency powers 1/2 (Delta, Theta, LowAlpha, HighAlpha)
/// 0xEC — EEG frequency powers 2/2 (LowBeta, HighBeta, LowGamma, MidGamma)
/// RawEEG (039afff4) — 20 bytes, 10 signed samples at 2 bytes each
///
/// Raw EEG samples also run through a `BlinkDetector`; each detected blink is passed to
/// `onBlink` as a `BlinkEvent`. Detection is off until the first 0xEA packet reports signal
/// quality, and while `poorSignal` exceeds `maxPoorSignal` — electrode contact noise looks
/// like a blink.
public final class ThinkGearParser {

    /// `poorSignal` above this (`.poor`, `.noSignal`) pauses blink detection.
    public static let defaultMaxPoorSignal = 50

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

    // MARK: - Blink detection

    private let blinkDetector: BlinkDetector
    private let maxPoorSignal: Int
    private let onBlink: ((BlinkEvent) -> Void)?
    private var signalKnown = false
    private var blinkSequence = 0

    public init(
        blinkDetector: BlinkDetector = BlinkDetector(),
        maxPoorSignal: Int = ThinkGearParser.defaultMaxPoorSignal,
        onBlink: ((BlinkEvent) -> Void)? = nil
    ) {
        self.blinkDetector = blinkDetector
        self.maxPoorSignal = maxPoorSignal
        self.onBlink = onBlink
    }

    /// Clear accumulated values, the blink count, and the detector for a new connection.
    public func reset() {
        poorSignal = 0; attention = 0; meditation = 0
        delta = 0; theta = 0; lowAlpha = 0; highAlpha = 0
        lowBeta = 0; highBeta = 0; lowGamma = 0; midGamma = 0
        signalKnown = false
        blinkSequence = 0
        blinkDetector.reset()
    }

    // MARK: - eSense packet parsing (0xEA / 0xEB / 0xEC)

    /// Parse data received from the eSense characteristic (039afff8).
    /// - Returns: Updated `BrainWaveData` snapshot, or `nil` for unknown packet types.
    public func parseEsense(_ data: Data) -> BrainWaveData? {
        let bytes = [UInt8](data)
        // MWM2 BLE eSense payloads start with a 2-byte prefix (00 00); the packet type is at
        // bytes[2]. Field offsets (6/8/10, 5/9/13/17) already count the prefix.
        // Matches the reference SDK (MWMleService: `byte packType = data[2]`).
        guard bytes.count >= 3 else { return nil }

        switch bytes[2] {
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

        let snapshot = makeSnapshot(rawEeg: samples)
        detectBlink(samples, at: snapshot.timestamp)
        return snapshot
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

    // MARK: - Private

    private func parseEA(_ bytes: [UInt8]) -> BrainWaveData? {
        guard bytes.count > 10 else { return nil }
        poorSignal = Int(bytes[6])
        attention  = Int(bytes[8])
        meditation = Int(bytes[10])
        signalKnown = true
        return makeSnapshot()
    }

    private func detectBlink(_ samples: [Int], at timestamp: Int64) {
        guard signalKnown, poorSignal <= maxPoorSignal else {
            blinkDetector.reset()  // warm up again once the signal recovers
            return
        }
        let strength = blinkDetector.process(samples)
        guard strength > 0 else { return }
        blinkSequence += 1
        onBlink?(BlinkEvent(timestampMs: timestamp, strength: strength, sequence: blinkSequence))
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
