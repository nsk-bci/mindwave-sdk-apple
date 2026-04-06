import Foundation

/// Connection state
public enum ConnectionState: Sendable {
    case disconnected
    case scanning
    case connecting
    case connected
    case error(Error)
}

extension ConnectionState: Equatable {
    public static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.scanning, .scanning),
             (.connecting, .connecting),
             (.connected, .connected),
             (.error, .error):
            return true
        default:
            return false
        }
    }
}

/// Selects which Bluetooth transport to use.
public enum TransportMode {
    /// BLE via CoreBluetooth. No pairing required. Default. iOS + macOS.
    case ble
    /// BT Classic via IOBluetooth RFCOMM SPP. macOS only. Requires pairing in System Settings.
    case btClassic
}

/// Common protocol shared by BLETransport, BTClassicTransport, and SimulatorTransport.
public protocol Transport: AnyObject {
    /// Received BrainWaveData stream
    var dataStream: AsyncStream<BrainWaveData> { get }

    /// Connection state stream
    var stateStream: AsyncStream<ConnectionState> { get }

    /// Connect to a device by address or name
    func connect(to deviceAddress: String) async throws

    /// Disconnect
    func disconnect() async

    /// Send a command byte to the headset
    func sendCommand(_ command: UInt8) async throws
}
