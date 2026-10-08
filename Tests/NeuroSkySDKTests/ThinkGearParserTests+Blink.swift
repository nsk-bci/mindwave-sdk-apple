import XCTest
@testable import NeuroSkySDK

/// Blink detection tests. Kept on `ThinkGearParserTests` so the CI filter
/// (`swift test --filter ThinkGearParserTests`) runs them.
extension ThinkGearParserTests {

    private final class FakeClock {
        var now: Int64 = 10_000
    }

    /// Fixed threshold so the tests check detection logic, not the provisional default.
    private static let threshold = 1_000

    private static let flat = [Int](repeating: 0, count: 10)

    private static func spike(_ amplitude: Int) -> [Int] {
        var s = flat
        s[5] = amplitude
        return s
    }

    /// Feeds a flat signal at the ~20 ms BLE packet interval until warm-up is over.
    private func warmedUpDetector() -> (BlinkDetector, FakeClock) {
        let clock = FakeClock()
        let detector = BlinkDetector(threshold: Self.threshold, clock: { clock.now })
        _ = detector.process(Self.flat)
        for _ in 0..<30 { clock.now += 20; _ = detector.process(Self.flat) }
        return (detector, clock)
    }

    // MARK: - BlinkDetector

    func test_blink_detectedWhenPeakToPeakReachesThreshold() {
        let (detector, clock) = warmedUpDetector()
        clock.now += 20
        XCTAssertEqual(detector.process(Self.spike(Self.threshold)), Self.threshold)
    }

    func test_blink_ignoresDeflectionBelowThreshold() {
        let (detector, clock) = warmedUpDetector()
        clock.now += 20
        XCTAssertEqual(detector.process(Self.spike(Self.threshold - 1)), 0)
    }

    func test_blink_suppressedDuringWarmup() {
        let clock = FakeClock()
        let detector = BlinkDetector(threshold: Self.threshold, clock: { clock.now })
        _ = detector.process(Self.flat)
        clock.now += 400
        XCTAssertEqual(detector.process(Self.spike(Self.threshold * 5)), 0)
    }

    func test_blink_suppressedWithinCooldown() {
        let (detector, clock) = warmedUpDetector()
        clock.now += 20
        XCTAssertEqual(detector.process(Self.spike(1_200)), 1_200)
        clock.now += 600
        XCTAssertEqual(detector.process(Self.spike(1_200)), 0)
        clock.now += 1
        XCTAssertEqual(detector.process(Self.spike(1_200)), 1_200)
    }

    func test_blink_peakToPeakCoversWholeWindow() {
        let (detector, clock) = warmedUpDetector()
        clock.now += 20
        _ = detector.process([Int](repeating: -600, count: 10))
        clock.now += 20
        XCTAssertEqual(detector.process([Int](repeating: 500, count: 10)), 1_100)
    }

    func test_blink_rearmsWarmupAfterStreamGap() {
        let (detector, clock) = warmedUpDetector()
        clock.now += BlinkDetector.restartGapMs + 1
        XCTAssertEqual(detector.process(Self.spike(Self.threshold * 5)), 0)
    }

    // MARK: - ThinkGearParser → BlinkEvent

    private final class BlinkHarness {
        let clock = FakeClock()
        var events: [BlinkEvent] = []
        private(set) var parser: ThinkGearParser!

        init() {
            let detector = BlinkDetector(threshold: ThinkGearParserTests.threshold, clock: { [clock] in clock.now })
            parser = ThinkGearParser(blinkDetector: detector, onBlink: { [unowned self] in self.events.append($0) })
        }

        /// 0xEA packet. The type byte is set at both [0] and [2] so the test holds for either
        /// eSense layout the parser reads (MWM2 sends `00 00 EA …`).
        func esense(poorSignal: UInt8) {
            var bytes = [UInt8](repeating: 0, count: 11)
            bytes[0] = 0xEA
            bytes[2] = 0xEA
            bytes[6] = poorSignal
            _ = parser.parseEsense(Data(bytes))
        }

        func raw(_ samples: [Int]) {
            clock.now += 20
            let data = Data(samples.flatMap { [UInt8(truncatingIfNeeded: $0 >> 8), UInt8(truncatingIfNeeded: $0)] })
            _ = parser.parseRawEeg(data)
        }

        func warmUp() {
            for _ in 0..<31 { raw(ThinkGearParserTests.flat) }
        }
    }

    func test_blink_parserEmitsEventWithStrengthAndSequence() {
        let h = BlinkHarness()
        h.esense(poorSignal: 0)
        h.warmUp()

        h.raw(Self.spike(1_500))
        for _ in 0..<10 { h.raw(Self.flat) }  // push the first spike out of the 100-sample window
        h.clock.now += 400                     // cooldown (600 ms) elapsed
        h.raw(Self.spike(1_300))

        XCTAssertEqual(h.events.map(\.sequence), [1, 2])
        XCTAssertEqual(h.events.map(\.strength), [1_500, 1_300])
    }

    func test_blink_parserSilentBeforeSignalQualityIsKnown() {
        let h = BlinkHarness()
        h.warmUp()
        h.raw(Self.spike(Self.threshold * 5))
        XCTAssertTrue(h.events.isEmpty)
    }

    func test_blink_parserSilentWhileSignalIsPoor() {
        let h = BlinkHarness()
        h.esense(poorSignal: 200)
        h.warmUp()
        h.raw(Self.spike(Self.threshold * 5))
        XCTAssertTrue(h.events.isEmpty)
    }

    func test_blink_parserRearmsWarmupWhenSignalRecovers() {
        let h = BlinkHarness()
        h.esense(poorSignal: 200)
        h.warmUp()
        h.esense(poorSignal: 0)

        h.raw(Self.spike(Self.threshold * 5))  // right after recovery = still warming up
        XCTAssertTrue(h.events.isEmpty)

        h.warmUp()
        h.raw(Self.spike(1_500))
        XCTAssertEqual(h.events.count, 1)
    }

    func test_blink_parserResetRestartsSequence() {
        let h = BlinkHarness()
        h.esense(poorSignal: 0)
        h.warmUp()
        h.raw(Self.spike(1_500))

        h.parser.reset()
        h.esense(poorSignal: 0)
        h.warmUp()
        h.raw(Self.spike(1_500))

        XCTAssertEqual(h.events.map(\.sequence), [1, 1])
    }
}
