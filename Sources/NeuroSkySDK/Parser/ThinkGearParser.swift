import Foundation

/// NeuroSky ThinkGear BLE 패킷 파서
///
/// 0xEA — Attention/Meditation/PoorSignal
/// 0xEB — EEG 주파수 파워 1/2 (Delta, Theta, LowAlpha, HighAlpha)
/// 0xEC — EEG 주파수 파워 2/2 (LowBeta, HighBeta, LowGamma, MidGamma)
/// RawEEG (039afff4) — 20바이트, 2바이트씩 10샘플
public final class ThinkGearParser {

    // MARK: - 누적 상태 (패킷이 여러 번 나뉘어 들어올 수 있으므로)

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

    // MARK: - eSense 패킷 파싱 (0xEA / 0xEB / 0xEC)

    /// eSense characteristic (039afff8) 수신 데이터 파싱
    /// - Returns: 업데이트된 BrainWaveData (poorSignal/attention/meditation 또는 EEG 파워 반영)
    public func parseEsense(_ data: Data) -> BrainWaveData? {
        let bytes = [UInt8](data)
        guard !bytes.isEmpty else { return nil }

        let packetType = bytes[0]

        switch packetType {
        case 0xEA:
            return parseEA(bytes)
        case 0xEB:
            return parseEB(bytes)
        case 0xEC:
            return parseEC(bytes)
        default:
            return nil
        }
    }

    /// Raw EEG characteristic (039afff4) 수신 데이터 파싱
    /// - Returns: rawEeg 필드가 채워진 BrainWaveData
    public func parseRawEeg(_ data: Data) -> BrainWaveData {
        let bytes = [UInt8](data)
        var samples: [Int] = []

        let count = bytes.count / 2
        for i in 0..<count {
            var value = (Int(bytes[i * 2]) << 8) | Int(bytes[i * 2 + 1])
            if value > 32768 { value -= 65536 }
            samples.append(value)
        }

        return makeSnapshot(rawEeg: samples)
    }

    // MARK: - 핸드셰이크 패킷 생성

    /// 명령 바이트를 포함한 20바이트 핸드셰이크 패킷 생성
    public static func buildHandshake(command: UInt8) -> Data {
        var bytes = [UInt8](repeating: 0x00, count: 20)
        bytes[0] = 0x77  // 헤더
        bytes[1] = 0x01  // 길이
        bytes[2] = command

        // 체크섬: (bytes[1] + ... + bytes[18]) XOR 0xFF AND 0xFF
        let sum = bytes[1..<19].reduce(0, { $0 + Int($1) })
        bytes[19] = UInt8((sum ^ 0xFF) & 0xFF)

        return Data(bytes)
    }

    // MARK: - BT Classic 전용

    /// BT Classic TLV에서 eSense 값 선택적 업데이트 후 스냅샷 반환
    ///
    /// nil인 파라미터는 이전 누적 값을 유지한다.
    public func updateAndSnapshot(poorSignal: Int? = nil, attention: Int? = nil, meditation: Int? = nil) -> BrainWaveData {
        if let v = poorSignal  { self.poorSignal  = v }
        if let v = attention   { self.attention   = v }
        if let v = meditation  { self.meditation  = v }
        return makeSnapshot()
    }

    /// BT Classic 0x83 EEG Power 파싱 (24바이트 = 8 × 3바이트 big-endian)
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
        delta    = int24(bytes, offset: 5)
        theta    = int24(bytes, offset: 9)
        lowAlpha = int24(bytes, offset: 13)
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
