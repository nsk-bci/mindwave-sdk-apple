import Foundation

/// NeuroSky MindWave SDK 진입점
///
/// BLE 우선 연결, 5초 내 실패 시 macOS에서는 BT Classic으로 자동 폴백.
///
/// ```swift
/// let sdk = NeuroSkySdk()
///
/// Task {
///     try await sdk.connect("MindWave Mobile")
///
///     for await data in sdk.dataStream {
///         print("Attention: \(data.attention)")
///         print("Signal: \(data.signalQuality)")
///     }
/// }
/// ```
@MainActor
public final class NeuroSkySdk {

    // MARK: - 공개 스트림
    //
    // SDK 소유의 단일 스트림을 노출한다.
    // activeTransport가 교체되어도 구독자는 동일한 스트림을 유지한다.

    public let dataStream: AsyncStream<BrainWaveData>
    public let stateStream: AsyncStream<ConnectionState>

    private let dataContinuation: AsyncStream<BrainWaveData>.Continuation
    private let stateContinuation: AsyncStream<ConnectionState>.Continuation

    // MARK: - 내부 상태

    private var activeTransport: (any Transport)?
    private var forwardTask: Task<Void, Never>?

    private let bleTransport = BLETransport()

    #if os(macOS)
    private let btClassicTransport = BTClassicTransport()
    #endif

    // MARK: - Init

    /// 실기기 연결 초기화
    public init() {
        var dataCont: AsyncStream<BrainWaveData>.Continuation!
        var stateCont: AsyncStream<ConnectionState>.Continuation!
        dataStream  = AsyncStream { dataCont  = $0 }
        stateStream = AsyncStream { stateCont = $0 }
        dataContinuation  = dataCont
        stateContinuation = stateCont
    }

    /// Simulator 모드 초기화 (실기기 불필요)
    public init(simulator mode: SimulatorTransport.Mode = .random) {
        var dataCont: AsyncStream<BrainWaveData>.Continuation!
        var stateCont: AsyncStream<ConnectionState>.Continuation!
        dataStream  = AsyncStream { dataCont  = $0 }
        stateStream = AsyncStream { stateCont = $0 }
        dataContinuation  = dataCont
        stateContinuation = stateCont

        let sim = SimulatorTransport(mode: mode)
        activeTransport = sim
        startForwarding(from: sim)
    }

    // MARK: - 연결

    /// 디바이스 이름(또는 주소)으로 연결
    ///
    /// iOS: BLE 전용
    /// macOS: BLE 우선 → 5초 내 실패 시 BT Classic 자동 폴백
    public func connect(_ deviceAddress: String) async throws {
        #if os(macOS)
        do {
            try await connectBLE(deviceAddress)
        } catch {
            // BLE 실패(타임아웃 포함) → BT Classic 폴백
            try await connectBTClassic(deviceAddress)
        }
        #else
        try await connectBLE(deviceAddress)
        #endif
    }

    /// 연결 해제
    public func disconnect() async {
        forwardTask?.cancel()
        forwardTask = nil
        await activeTransport?.disconnect()
        activeTransport = nil
    }

    /// 헤드셋에 명령 전송
    public func sendCommand(_ command: UInt8) async throws {
        try await activeTransport?.sendCommand(command)
    }

    // MARK: - 편의 메서드

    public func startRawEeg() async throws {
        try await sendCommand(NeuroSkyCommand.startRawEeg)
    }

    public func stopRawEeg() async throws {
        try await sendCommand(NeuroSkyCommand.stopRawEeg)
    }

    /// 50Hz 노치 필터 (중국/유럽)
    public func setNotch50Hz() async throws {
        try await sendCommand(NeuroSkyCommand.notch50Hz)
    }

    /// 60Hz 노치 필터 (한국/미국)
    public func setNotch60Hz() async throws {
        try await sendCommand(NeuroSkyCommand.notch60Hz)
    }

    // MARK: - Private

    private func connectBLE(_ deviceAddress: String) async throws {
        switchTransport(to: bleTransport)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await self.bleTransport.connect(to: deviceAddress) }
            group.addTask {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                throw TransportError.bleTimeout
            }
            try await group.next()
            group.cancelAll()
        }
    }

    #if os(macOS)
    private func connectBTClassic(_ deviceAddress: String) async throws {
        switchTransport(to: btClassicTransport)
        try await btClassicTransport.connect(to: deviceAddress)
    }
    #endif

    /// activeTransport를 교체하고 스트림 포워딩을 재시작
    private func switchTransport(to transport: any Transport) {
        forwardTask?.cancel()
        activeTransport = transport
        startForwarding(from: transport)
    }

    /// transport의 dataStream/stateStream을 SDK의 단일 스트림으로 포워딩
    private func startForwarding(from transport: any Transport) {
        let dataCont  = dataContinuation
        let stateCont = stateContinuation
        forwardTask = Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await data in transport.dataStream {
                        guard !Task.isCancelled else { break }
                        dataCont.yield(data)
                    }
                }
                group.addTask {
                    for await state in transport.stateStream {
                        guard !Task.isCancelled else { break }
                        stateCont.yield(state)
                    }
                }
            }
        }
    }
}

// MARK: - Error

public enum TransportError: Error {
    case bleTimeout
}
