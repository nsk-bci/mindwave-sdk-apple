import Foundation

/// EEG 헤드셋에서 수신한 뇌파 데이터 스냅샷
public struct BrainWaveData: Sendable {
    /// 데이터 수신 시각 (Unix milliseconds)
    public let timestamp: Int64

    /// 신호 품질 (0 = 완벽, 200 = 무신호)
    public let poorSignal: Int

    /// 집중도 (0~100)
    public let attention: Int

    /// 명상도 (0~100)
    public let meditation: Int

    // MARK: - EEG 주파수 파워 (0xEB / 0xEC 패킷)

    public let delta: Int       // 0.5~2.75 Hz
    public let theta: Int       // 3.5~6.75 Hz
    public let lowAlpha: Int    // 7.5~9.25 Hz
    public let highAlpha: Int   // 10~11.75 Hz
    public let lowBeta: Int     // 13~16.75 Hz
    public let highBeta: Int    // 18~29.75 Hz
    public let lowGamma: Int    // 31~39.75 Hz
    public let midGamma: Int    // 41~49.75 Hz

    /// Raw EEG 샘플 (패킷당 10개, 512 Hz)
    public let rawEeg: [Int]

    /// 눈 깜빡임 강도 (0이면 미감지)
    public let eyeBlink: Int

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
        rawEeg: [Int] = [],
        eyeBlink: Int = 0
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
        self.eyeBlink = eyeBlink
    }

    /// 신호 품질 enum
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
