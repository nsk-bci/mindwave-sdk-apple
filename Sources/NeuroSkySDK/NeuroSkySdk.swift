import Foundation
import CoreBluetooth

/// Entry point for the NeuroSky MindWave Apple SDK.
///
/// BLE is used by default. Pass `mode: .btClassic` on macOS to connect via
/// Bluetooth Classic SPP instead (requires the headset to be paired first in
/// System Settings → Bluetooth).
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

    // MARK: - Public streams
    //
    // A single pair of streams is exposed by the SDK.
    // Subscribers keep the same stream even if the active transport is swapped.

    public let dataStream: AsyncStream<BrainWaveData>
    public let stateStream: AsyncStream<ConnectionState>

    private let dataContinuation: AsyncStream<BrainWaveData>.Continuation
    private let stateContinuation: AsyncStream<ConnectionState>.Continuation

    // MARK: - Internal state

    private var activeTransport: (any Transport)?
    private var forwardTask: Task<Void, Never>?
    private var deviceFinder: BLEDeviceFinder?

    private lazy var bleTransport = BLETransport()

    #if os(macOS)
    private lazy var btClassicTransport = BTClassicTransport()
    #endif

    // MARK: - Init

    /// Initialize for use with a real headset.
    public init() {
        var dataCont: AsyncStream<BrainWaveData>.Continuation!
        var stateCont: AsyncStream<ConnectionState>.Continuation!
        dataStream  = AsyncStream { dataCont  = $0 }
        stateStream = AsyncStream { stateCont = $0 }
        dataContinuation  = dataCont
        stateContinuation = stateCont
    }

    /// Initialize in simulator mode — no real headset required.
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

    // MARK: - Connection

    /// Connect to the headset by device name or identifier string.
    ///
    /// - Parameters:
    ///   - deviceAddress: The peripheral name (e.g. `"MindWave Mobile"`) or, for BLE,
    ///     the `CBPeripheral.identifier` UUID string returned by `findDeviceIdentifier(_:timeout:)`.
    ///   - mode: Transport to use. Defaults to `.ble` (iOS + macOS).
    ///     Pass `.btClassic` on macOS to use Bluetooth Classic SPP.
    ///   - timeout: Maximum seconds to wait for the BLE scan + connect handshake.
    ///     Throws `BLEError.deviceNotFound` if the timer expires. Ignored for BT Classic
    ///     and simulator modes. Default: 10 s.
    public func connect(
        _ deviceAddress: String,
        mode: TransportMode = .ble,
        timeout: TimeInterval = 10
    ) async throws {
        // Simulator mode: use the already-configured SimulatorTransport directly.
        if let sim = activeTransport as? SimulatorTransport {
            try await sim.connect(to: deviceAddress)
            return
        }

        switch mode {
        case .ble:
            try await connectBLE(deviceAddress, timeout: timeout)
        case .btClassic:
            #if os(macOS)
            try await connectBTClassic(deviceAddress)
            #else
            throw TransportError.btClassicNotAvailableOniOS
            #endif
        }
    }

    /// Disconnect from the headset and release all resources.
    public func disconnect() async {
        forwardTask?.cancel()
        forwardTask = nil
        await activeTransport?.disconnect()
        activeTransport = nil
        // Guarantee .disconnected is always emitted on sdk.stateStream.
        // forwardTask is already cancelled so it cannot forward the transport's
        // .disconnected event — emit it directly here instead.
        stateContinuation.yield(.disconnected)
    }

    /// Send a raw command byte to the headset.
    public func sendCommand(_ command: UInt8) async throws {
        try await activeTransport?.sendCommand(command)
    }

    // MARK: - Convenience commands

    public func startRawEeg() async throws {
        try await sendCommand(NeuroSkyCommand.startRawEeg)
    }

    public func stopRawEeg() async throws {
        try await sendCommand(NeuroSkyCommand.stopRawEeg)
    }

    /// Apply 50 Hz notch filter (China / Europe mains frequency).
    public func setNotch50Hz() async throws {
        try await sendCommand(NeuroSkyCommand.notch50Hz)
    }

    /// Apply 60 Hz notch filter (Korea / USA mains frequency).
    public func setNotch60Hz() async throws {
        try await sendCommand(NeuroSkyCommand.notch60Hz)
    }

    // MARK: - Device discovery

    /// Scan for a BLE peripheral whose name contains `deviceName` and return
    /// its `CBPeripheral.identifier` UUID string.
    ///
    /// The returned string can be passed directly to `connect(_:mode:)` as the
    /// `deviceAddress` argument.  Cache the result to avoid scanning on every
    /// app launch.
    ///
    /// - Parameters:
    ///   - deviceName: Substring to match against the peripheral's advertised name
    ///     (case-insensitive).
    ///   - timeout: How long to scan before giving up. Default: 10 seconds.
    /// - Returns: The peripheral's UUID string, or `nil` if none was found within
    ///   the timeout.
    public func findDeviceIdentifier(
        _ deviceName: String,
        timeout: TimeInterval = 10
    ) async -> String? {
        return await withCheckedContinuation { continuation in
            let finder = BLEDeviceFinder(name: deviceName, timeout: timeout) { [weak self] uuid in
                self?.deviceFinder = nil   // Release once done
                continuation.resume(returning: uuid)
            }
            deviceFinder = finder  // Keep finder alive until the callback fires
            finder.start()
        }
    }

    // MARK: - Private

    private func connectBLE(_ deviceAddress: String, timeout: TimeInterval) async throws {
        switchTransport(to: bleTransport)
        try await bleTransport.connect(to: deviceAddress, timeout: timeout)
    }

    #if os(macOS)
    private func connectBTClassic(_ deviceAddress: String) async throws {
        switchTransport(to: btClassicTransport)
        try await btClassicTransport.connect(to: deviceAddress)
    }
    #endif

    /// Replace the active transport and restart stream forwarding.
    private func switchTransport(to transport: any Transport) {
        forwardTask?.cancel()
        activeTransport = transport
        startForwarding(from: transport)
    }

    /// Forward dataStream and stateStream from the transport to the SDK's
    /// single unified streams.
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

// MARK: - BLE device finder (internal helper)

/// One-shot CBCentralManager that scans until a matching peripheral is found
/// or the timeout expires.
private final class BLEDeviceFinder: NSObject, CBCentralManagerDelegate {

    private let targetName: String
    private let timeout: TimeInterval
    private let completion: (String?) -> Void

    private var central: CBCentralManager?
    private var timeoutTask: Task<Void, Never>?
    private var finished = false

    init(name: String, timeout: TimeInterval, completion: @escaping (String?) -> Void) {
        self.targetName = name
        self.timeout    = timeout
        self.completion = completion
        super.init()
    }

    func start() {
        central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            finish(with: nil)
            return
        }
        central.scanForPeripherals(withServices: nil, options: nil)
        timeoutTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            self.finish(with: nil)
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = peripheral.name ?? ""
        guard name.lowercased().contains(targetName.lowercased()) else { return }
        finish(with: peripheral.identifier.uuidString)
    }

    private func finish(with result: String?) {
        guard !finished else { return }
        finished = true
        timeoutTask?.cancel()
        central?.stopScan()
        central = nil
        completion(result)
    }
}

// MARK: - Errors

public enum TransportError: Error {
    /// BT Classic transport is only available on macOS.
    case btClassicNotAvailableOniOS
}
