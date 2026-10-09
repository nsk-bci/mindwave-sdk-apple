import XCTest
@testable import NeuroSkySDK

/// Determinism and value-range tests for the test-only `SimulatorTransport`.
final class SimulatorTransportTests: XCTestCase {

    private static let samples = 200

    private func draw(_ mode: SimulatorTransport.Mode, seed: UInt64 = SimulatorTransport.defaultSeed) -> [BrainWaveData] {
        let sim = SimulatorTransport(mode: mode, seed: seed)
        return (0..<Self.samples).map { _ in sim.generateData() }
    }

    // MARK: - Determinism

    func test_sameSeed_producesIdenticalSequence() {
        let a = draw(.random)
        let b = draw(.random)
        XCTAssertEqual(a.map(\.attention), b.map(\.attention))
        XCTAssertEqual(a.flatMap(\.rawEeg), b.flatMap(\.rawEeg))
    }

    func test_differentSeed_producesDifferentSequence() {
        XCTAssertNotEqual(draw(.random, seed: 1).map(\.attention), draw(.random, seed: 2).map(\.attention))
    }

    func test_seededGenerator_isReproducible() {
        var g1 = SeededGenerator(seed: 42)
        var g2 = SeededGenerator(seed: 42)
        XCTAssertEqual((0..<16).map { _ in g1.next() }, (0..<16).map { _ in g2.next() })
    }

    // MARK: - Mode ranges

    func test_random_staysWithinRanges() {
        for d in draw(.random) {
            XCTAssertTrue((0...10).contains(d.poorSignal))
            XCTAssertTrue((20...80).contains(d.attention))
            XCTAssertTrue((20...80).contains(d.meditation))
            XCTAssertEqual(d.rawEeg.count, 10)
            XCTAssertTrue(d.rawEeg.allSatisfy { (-512...512).contains($0) })
        }
    }

    func test_focused_highAttention_goodSignal() {
        for d in draw(.focused) {
            XCTAssertTrue((70...95).contains(d.attention))
            XCTAssertTrue((40...60).contains(d.meditation))
            XCTAssertEqual(d.signalQuality, .good)
        }
    }

    func test_relaxed_highMeditation_goodSignal() {
        for d in draw(.relaxed) {
            XCTAssertTrue((20...45).contains(d.attention))
            XCTAssertTrue((70...95).contains(d.meditation))
            XCTAssertEqual(d.signalQuality, .good)
        }
    }

    func test_poorSignal_noSignal_noESense() {
        for d in draw(.poorSignal) {
            XCTAssertEqual(d.poorSignal, 200)
            XCTAssertEqual(d.signalQuality, .noSignal)
            XCTAssertEqual(d.attention, 0)
            XCTAssertEqual(d.meditation, 0)
        }
    }
}
