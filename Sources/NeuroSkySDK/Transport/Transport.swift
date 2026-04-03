import Foundation

/// 연결 상태
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

/// BLE / BT Classic 공통 Transport 프로토콜
public protocol Transport: AnyObject {
    /// 수신된 BrainWaveData 스트림
    var dataStream: AsyncStream<BrainWaveData> { get }

    /// 연결 상태 스트림
    var stateStream: AsyncStream<ConnectionState> { get }

    /// 디바이스 주소(또는 이름)로 연결
    func connect(to deviceAddress: String) async throws

    /// 연결 해제
    func disconnect() async

    /// 헤드셋에 명령 전송
    func sendCommand(_ command: UInt8) async throws
}
