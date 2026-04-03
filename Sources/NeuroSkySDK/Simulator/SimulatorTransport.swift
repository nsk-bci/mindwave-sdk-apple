import Foundation

/// 실기기 없이 개발할 때 사용하는 Simulator Transport
///
/// 1초마다 BrainWaveData를 자동 생성한다.
/// Debug 빌드에서만 사용 권장 (#if DEBUG).
public final class SimulatorTransport: Transport {

    // MARK: - 시뮬레이터 모드

    public enum Mode {
        /// 랜덤 값
        case random
        /// 집중 상태: attention 높음, meditation 중간
        case focused
        /// 이완 상태: attention 낮음, meditation 높음
        case relaxed
        /// 신호 불량: poorSignal = 200
        case poorSignal
    }

    // MARK: - AsyncStream 출력

    public let dataStream: AsyncStream<BrainWaveData>
    public let stateStream: AsyncStream<ConnectionState>

    private let dataContinuation: AsyncStream<BrainWaveData>.Continuation
    private let stateContinuation: AsyncStream<ConnectionState>.Continuation

    // MARK: - 상태

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
        try await Task.sleep(nanoseconds: 300_000_000)  // 0.3초 가짜 연결 지연
        stateContinuation.yield(.connected)
        startEmitting()
    }

    public func disconnect() async {
        timerTask?.cancel()
        timerTask = nil
        stateContinuation.yield(.disconnected)
    }

    public func sendCommand(_ command: UInt8) async throws {
        // 시뮬레이터는 명령 무시
    }

    // MARK: - Private

    private func startEmitting() {
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1초
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
