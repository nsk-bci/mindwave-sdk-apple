import Foundation

/// Snapshot of EEG data received from the headset
public struct BrainWaveData: Sendable {
    /// Timestamp of reception (Unix milliseconds)
    public let timestamp: Int64

    /// Signal quality (0 = perfect contact, 200 = no signal)
    public let poorSignal: Int

    /// eSense attention level (0~100)
    public let attention: Int

    /// eSense meditation level (0~100)
    public let meditation: Int

    // MARK: - EEG frequency band powers (0xEB / 0xEC packets)

    public let delta: Int       // 0.5~2.75 Hz
    public let theta: Int       // 3.5~6.75 Hz
    public let lowAlpha: Int    // 7.5~9.25 Hz
    public let highAlpha: Int   // 10~11.75 Hz
    public let lowBeta: Int     // 13~16.75 Hz
    public let highBeta: Int    // 18~29.75 Hz
    public let lowGamma: Int    // 31~39.75 Hz
    public let midGamma: Int    // 41~49.75 Hz

    /// Raw EEG samples (10 samples per packet, 512 Hz)
    public let rawEeg: [Int]

    public init(
        timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        poorSignal: Int = 0,
        attention: Int = 0,
        meditation: Int = 0,
        delta: Int = 0,
        theta: Int = 0,
        lowAlpha: Int = 0,
        highAlpha: Int = 0,
        lowBeta: Int = 0,
        highBeta: Int = 0,
        lowGamma: Int = 0,
        midGamma: Int = 0,
        rawEeg: [Int] = []
    ) {
        self.timestamp = timestamp
        self.poorSignal = poorSignal
        self.attention = attention
        self.meditation = meditation
        self.delta = delta
        self.theta = theta
        self.lowAlpha = lowAlpha
        self.highAlpha = highAlpha
        self.lowBeta = lowBeta
        self.highBeta = highBeta
        self.lowGamma = lowGamma
        self.midGamma = midGamma
        self.rawEeg = rawEeg
    }

    /// Derived signal quality enum
    public var signalQuality: SignalQuality {
        switch poorSignal {
        case 200:       return .noSignal
        case 51...:     return .poor
        case 1...:      return .fair
        default:        return .good
        }
    }
}

public enum SignalQuality: String, Sendable {
    case noSignal = "NO_SIGNAL"
    case poor     = "POOR"
    case fair     = "FAIR"
    case good     = "GOOD"
}
