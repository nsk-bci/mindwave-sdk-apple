import Foundation

/// Simulator transport for development without a real headset.
///
/// Emits synthetic `BrainWaveData` once per second.
/// Recommended for use in `#if DEBUG` blocks only.
public final class SimulatorTransport: Transport {

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
    private var timerTask: Task<Void, Never>?

    // MARK: - Init

    public init(mode: Mode = .random) {
        self.mode = mode

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

    private func generateData() -> BrainWaveData {
        switch mode {
        case .random:
            return BrainWaveData(
                poorSignal: Int.random(in: 0...10),
                attention:  Int.random(in: 20...80),
                meditation: Int.random(in: 20...80),
                delta:      Int.random(in: 100_000...500_000),
                theta:      Int.random(in: 50_000...200_000),
                lowAlpha:   Int.random(in: 30_000...150_000),
                highAlpha:  Int.random(in: 30_000...150_000),
                lowBeta:    Int.random(in: 20_000...100_000),
                highBeta:   Int.random(in: 10_000...80_000),
                lowGamma:   Int.random(in: 5_000...50_000),
                midGamma:   Int.random(in: 5_000...50_000),
                rawEeg:     (0..<10).map { _ in Int.random(in: -512...512) }
            )

        case .focused:
            return BrainWaveData(
                poorSignal: 0,
                attention:  Int.random(in: 70...95),
                meditation: Int.random(in: 40...60),
                delta:      Int.random(in: 100_000...200_000),
                theta:      Int.random(in: 80_000...150_000),
                lowAlpha:   Int.random(in: 50_000...120_000),
                highAlpha:  Int.random(in: 50_000...120_000),
                lowBeta:    Int.random(in: 80_000...150_000),
                highBeta:   Int.random(in: 60_000...120_000),
                lowGamma:   Int.random(in: 20_000...60_000),
                midGamma:   Int.random(in: 20_000...60_000),
                rawEeg:     (0..<10).map { _ in Int.random(in: -256...256) }
            )

        case .relaxed:
            return BrainWaveData(
                poorSignal: 0,
                attention:  Int.random(in: 20...45),
                meditation: Int.random(in: 70...95),
                delta:      Int.random(in: 300_000...600_000),
                theta:      Int.random(in: 200_000...400_000),
                lowAlpha:   Int.random(in: 150_000...300_000),
                highAlpha:  Int.random(in: 150_000...300_000),
                lowBeta:    Int.random(in: 20_000...60_000),
                highBeta:   Int.random(in: 10_000...40_000),
                lowGamma:   Int.random(in: 5_000...20_000),
                midGamma:   Int.random(in: 5_000...20_000),
                rawEeg:     (0..<10).map { _ in Int.random(in: -128...128) }
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
