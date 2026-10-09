import Foundation

/// Test-only transport that emits synthetic `BrainWaveData` once per second.
///
/// Internal: reachable from the test target via `@testable import`. Uses a seeded
/// generator, so a given seed and mode always produce the same sequence.
final class SimulatorTransport: Transport {

    static let defaultSeed: UInt64 = 7

    // MARK: - Simulator modes

    public enum Mode {
        /// Random attention and meditation values
        case random
        /// High attention, moderate meditation — focused state
        case focused
        /// Low attention, high meditation — relaxed state
        case relaxed
        /// poorSignal = 200 — no signal / error handling test
        case poorSignal
    }

    // MARK: - AsyncStream output

    public let dataStream: AsyncStream<BrainWaveData>
    public let stateStream: AsyncStream<ConnectionState>

    private let dataContinuation: AsyncStream<BrainWaveData>.Continuation
    private let stateContinuation: AsyncStream<ConnectionState>.Continuation

    // MARK: - State

    private var mode: Mode
    private var rng: SeededGenerator
    private var timerTask: Task<Void, Never>?

    // MARK: - Init

    init(mode: Mode = .random, seed: UInt64 = SimulatorTransport.defaultSeed) {
        self.mode = mode
        self.rng = SeededGenerator(seed: seed)

        var dataCont: AsyncStream<BrainWaveData>.Continuation!
        var stateCont: AsyncStream<ConnectionState>.Continuation!

        dataStream  = AsyncStream { dataCont  = $0 }
        stateStream = AsyncStream { stateCont = $0 }

        dataContinuation  = dataCont
        stateContinuation = stateCont
    }

    public func setMode(_ mode: Mode) {
        self.mode = mode
    }

    // MARK: - Transport

    public func connect(to deviceAddress: String) async throws {
        stateContinuation.yield(.connecting)
        try await Task.sleep(nanoseconds: 300_000_000)  // 0.3 s simulated delay
        stateContinuation.yield(.connected)
        startEmitting()
    }

    public func disconnect() async {
        timerTask?.cancel()
        timerTask = nil
        stateContinuation.yield(.disconnected)
    }

    public func sendCommand(_ command: UInt8) async throws {
        // Simulator ignores all commands
    }

    // MARK: - Private

    private func startEmitting() {
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 s
                guard !Task.isCancelled else { break }
                dataContinuation.yield(generateData())
            }
        }
    }

    /// Internal so tests can draw samples without the 1 s emission delay.
    func generateData() -> BrainWaveData {
        switch mode {
        case .random:
            return BrainWaveData(
                poorSignal: Int.random(in: 0...10, using: &rng),
                attention:  Int.random(in: 20...80, using: &rng),
                meditation: Int.random(in: 20...80, using: &rng),
                delta:      Int.random(in: 100_000...500_000, using: &rng),
                theta:      Int.random(in: 50_000...200_000, using: &rng),
                lowAlpha:   Int.random(in: 30_000...150_000, using: &rng),
                highAlpha:  Int.random(in: 30_000...150_000, using: &rng),
                lowBeta:    Int.random(in: 20_000...100_000, using: &rng),
                highBeta:   Int.random(in: 10_000...80_000, using: &rng),
                lowGamma:   Int.random(in: 5_000...50_000, using: &rng),
                midGamma:   Int.random(in: 5_000...50_000, using: &rng),
                rawEeg:     (0..<10).map { _ in Int.random(in: -512...512, using: &rng) }
            )

        case .focused:
            return BrainWaveData(
                poorSignal: 0,
                attention:  Int.random(in: 70...95, using: &rng),
                meditation: Int.random(in: 40...60, using: &rng),
                delta:      Int.random(in: 100_000...200_000, using: &rng),
                theta:      Int.random(in: 80_000...150_000, using: &rng),
                lowAlpha:   Int.random(in: 50_000...120_000, using: &rng),
                highAlpha:  Int.random(in: 50_000...120_000, using: &rng),
                lowBeta:    Int.random(in: 80_000...150_000, using: &rng),
                highBeta:   Int.random(in: 60_000...120_000, using: &rng),
                lowGamma:   Int.random(in: 20_000...60_000, using: &rng),
                midGamma:   Int.random(in: 20_000...60_000, using: &rng),
                rawEeg:     (0..<10).map { _ in Int.random(in: -256...256, using: &rng) }
            )

        case .relaxed:
            return BrainWaveData(
                poorSignal: 0,
                attention:  Int.random(in: 20...45, using: &rng),
                meditation: Int.random(in: 70...95, using: &rng),
                delta:      Int.random(in: 300_000...600_000, using: &rng),
                theta:      Int.random(in: 200_000...400_000, using: &rng),
                lowAlpha:   Int.random(in: 150_000...300_000, using: &rng),
                highAlpha:  Int.random(in: 150_000...300_000, using: &rng),
                lowBeta:    Int.random(in: 20_000...60_000, using: &rng),
                highBeta:   Int.random(in: 10_000...40_000, using: &rng),
                lowGamma:   Int.random(in: 5_000...20_000, using: &rng),
                midGamma:   Int.random(in: 5_000...20_000, using: &rng),
                rawEeg:     (0..<10).map { _ in Int.random(in: -128...128, using: &rng) }
            )

        case .poorSignal:
            return BrainWaveData(
                poorSignal: 200,
                attention:  0,
                meditation: 0
            )
        }
    }
}

/// SplitMix64 — small, fast, deterministic generator for reproducible simulator data.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
