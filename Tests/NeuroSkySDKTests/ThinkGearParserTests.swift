import XCTest
@testable import NeuroSkySDK

final class ThinkGearParserTests: XCTestCase {

    var parser: ThinkGearParser!

    override func setUp() {
        parser = ThinkGearParser()
    }

    // MARK: - 0xEA 패킷

    func test_parseEA_extractsAttentionMeditationPoorSignal() {
        var bytes = [UInt8](repeating: 0, count: 11)
        bytes[0]  = 0xEA
        bytes[6]  = 30   // poorSignal
        bytes[8]  = 75   // attention
        bytes[10] = 60   // meditation

        let result = parser.parseEsense(Data(bytes))

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.poorSignal, 30)
        XCTAssertEqual(result?.attention,  75)
        XCTAssertEqual(result?.meditation, 60)
    }

    func test_parseEA_tooShort_returnsNil() {
        let bytes: [UInt8] = [0xEA, 0x00]
        XCTAssertNil(parser.parseEsense(Data(bytes)))
    }

    // MARK: - 0xEB 패킷

    func test_parseEB_extractsFrequencyBand1() {
        var bytes = [UInt8](repeating: 0, count: 20)
        bytes[0] = 0xEB
        // Delta: offset 5~7 = 0x01, 0x86, 0xA0 → 100000
        bytes[5] = 0x01; bytes[6] = 0x86; bytes[7] = 0xA0
        // Theta: offset 9~11 = 0x00, 0xC3, 0x50 → 50000
        bytes[9] = 0x00; bytes[10] = 0xC3; bytes[11] = 0x50

        let result = parser.parseEsense(Data(bytes))

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.delta, 100000)
        XCTAssertEqual(result?.theta, 50000)
    }

    // MARK: - Raw EEG

    func test_parseRawEeg_10Samples() {
        // 20바이트 = 10샘플
        var bytes = [UInt8](repeating: 0, count: 20)
        // 샘플 0: 0x01 0x00 = 256
        bytes[0] = 0x01; bytes[1] = 0x00
        // 샘플 1: 0x80 0x01 = 32769 → 부호처리 후 -32767
        bytes[2] = 0x80; bytes[3] = 0x01

        let result = parser.parseRawEeg(Data(bytes))

        XCTAssertEqual(result.rawEeg.count, 10)
        XCTAssertEqual(result.rawEeg[0], 256)
        XCTAssertEqual(result.rawEeg[1], -32767)
    }

    // MARK: - 핸드셰이크 패킷

    func test_buildHandshake_checksumCorrect() {
        let packet = [UInt8](ThinkGearParser.buildHandshake(command: NeuroSkyCommand.startEsense))

        XCTAssertEqual(packet.count, 20)
        XCTAssertEqual(packet[0], 0x77)
        XCTAssertEqual(packet[2], NeuroSkyCommand.startEsense)

        // 체크섬 검증
        let sum = packet[1..<19].reduce(0, { $0 + Int($1) })
        let expected = UInt8((sum ^ 0xFF) & 0xFF)
        XCTAssertEqual(packet[19], expected)
    }

    // MARK: - SignalQuality

    func test_signalQuality_levels() {
        XCTAssertEqual(BrainWaveData(poorSignal: 0).signalQuality,   .good)
        XCTAssertEqual(BrainWaveData(poorSignal: 25).signalQuality,  .fair)
        XCTAssertEqual(BrainWaveData(poorSignal: 100).signalQuality, .poor)
        XCTAssertEqual(BrainWaveData(poorSignal: 200).signalQuality, .noSignal)
    }
}
