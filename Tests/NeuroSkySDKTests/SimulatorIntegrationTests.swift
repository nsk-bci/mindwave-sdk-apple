import XCTest
@testable import NeuroSkySDK

/// Virtual "real device" integration tests using SimulatorTransport.
///
/// Covers the full lifecycle that would occur with a physical MindWave headset:
///   connect → receive data → verify values → disconnect
@MainActor
final class SimulatorIntegrationTests: XCTestCase {

    // MARK: - Connection lifecycle

    func test_connect_yieldsConnectingThenConnected() async throws {
        let sdk = NeuroSkySdk(simulator: .random)
        var states: [ConnectionState] = []

        let collectTask = Task {
            for await state in sdk.stateStream {
                states.append(state)
                if state == .connected { break }
            }
        }

        try await sdk.connect("sim")
        await collectTask.value

        XCTAssertEqual(states, [.connecting, .connected])
    }

    func test_disconnect_yieldsDisconnected() async throws {
        let sdk = NeuroSkySdk(simulator: .random)

        try await sdk.connect("sim")

        var receivedDisconnected = false
        let collectTask = Task {
            for await state in sdk.stateStream {
                if state == .disconnected { receivedDisconnected = true; break }
            }
        }

        await sdk.disconnect()
        await collectTask.value

        XCTAssertTrue(receivedDisconnected)
    }

    // MARK: - Data stream

    func test_focused_attentionInExpectedRange() async throws {
        let sdk = NeuroSkySdk(simulator: .focused)
        try await sdk.connect("sim")

        let data = try await firstData(from: sdk)

        XCTAssertEqual(data.poorSignal, 0)
        XCTAssertGreaterThanOrEqual(data.attention, 70)
        XCTAssertLessThanOrEqual(data.attention, 95)
        XCTAssertGreaterThanOrEqual(data.meditation, 40)
        XCTAssertLessThanOrEqual(data.meditation, 60)

        await sdk.disconnect()
    }

    func test_relaxed_meditationInExpectedRange() async throws {
        let sdk = NeuroSkySdk(simulator: .relaxed)
        try await sdk.connect("sim")

        let data = try await firstData(from: sdk)

        XCTAssertEqual(data.poorSignal, 0)
        XCTAssertGreaterThanOrEqual(data.meditation, 70)
        XCTAssertLessThanOrEqual(data.meditation, 95)
        XCTAssertGreaterThanOrEqual(data.attention, 20)
        XCTAssertLessThanOrEqual(data.attention, 45)

        await sdk.disconnect()
    }

    func test_poorSignal_signalQualityIsNoSignal() async throws {
        let sdk = NeuroSkySdk(simulator: .poorSignal)
        try await sdk.connect("sim")

        let data = try await firstData(from: sdk)

        XCTAssertEqual(data.poorSignal, 200)
        XCTAssertEqual(data.signalQuality, .noSignal)

        await sdk.disconnect()
    }

    func test_random_eegBandsArePositive() async throws {
        let sdk = NeuroSkySdk(simulator: .random)
        try await sdk.connect("sim")

        let data = try await firstData(from: sdk)

        XCTAssertGreaterThan(data.delta,    0)
        XCTAssertGreaterThan(data.theta,    0)
        XCTAssertGreaterThan(data.lowAlpha, 0)

        await sdk.disconnect()
    }

    func test_rawEeg_has10SamplesPerPacket() async throws {
        let sdk = NeuroSkySdk(simulator: .random)
        try await sdk.connect("sim")

        let data = try await firstData(from: sdk)

        XCTAssertEqual(data.rawEeg.count, 10)

        await sdk.disconnect()
    }

    func test_rawEeg_samplesInValidRange() async throws {
        let sdk = NeuroSkySdk(simulator: .random)
        try await sdk.connect("sim")

        let data = try await firstData(from: sdk)

        for sample in data.rawEeg {
            XCTAssertGreaterThanOrEqual(sample, -512)
            XCTAssertLessThanOrEqual(sample, 512)
        }

        await sdk.disconnect()
    }

    // MARK: - Multiple packets

    func test_receivesMultiplePacketsOverTime() async throws {
        let sdk = NeuroSkySdk(simulator: .focused)
        try await sdk.connect("sim")

        var count = 0
        let collectTask = Task {
            for await _ in sdk.dataStream {
                count += 1
                if count >= 3 { break }
            }
        }

        // SimulatorTransport emits every 1 s — wait up to 5 s
        try await Task.sleep(nanoseconds: 4_000_000_000)
        collectTask.cancel()
        await sdk.disconnect()

        XCTAssertGreaterThanOrEqual(count, 2, "Expected at least 2 packets in 4 seconds")
    }

    // MARK: - sendCommand (no-op in simulator)

    func test_sendCommand_doesNotThrow() async throws {
        let sdk = NeuroSkySdk(simulator: .random)
        try await sdk.connect("sim")

        await XCTAssertNoThrowAsync(try await sdk.startRawEeg())
        await XCTAssertNoThrowAsync(try await sdk.stopRawEeg())
        await XCTAssertNoThrowAsync(try await sdk.setNotch60Hz())
        await XCTAssertNoThrowAsync(try await sdk.setNotch50Hz())

        await sdk.disconnect()
    }

    // MARK: - Helpers

    /// Collects the first BrainWaveData packet with a 5-second timeout.
    private func firstData(from sdk: NeuroSkySdk) async throws -> BrainWaveData {
        try await withThrowingTaskGroup(of: BrainWaveData.self) { group in
            group.addTask {
                for await data in sdk.dataStream { return data }
                throw XCTestError(.timeoutWhileWaiting)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                throw XCTestError(.timeoutWhileWaiting)
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

// MARK: - Async assert helpers

func XCTAssertNoThrowAsync(
    _ expression: @autoclosure () async throws -> Void,
    _ message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
    } catch {
        XCTFail("Unexpected throw: \(error). \(message)", file: file, line: line)
    }
}
