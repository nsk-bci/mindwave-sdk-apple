# API Reference — NeuroSky MindWave SDK (Apple)

---

## NeuroSkySdk

메인 진입점. `@MainActor` 클래스.

### 초기화

```swift
// 실기기 연결
init()

// Simulator 모드
init(simulator mode: SimulatorTransport.Mode)
```

### 프로퍼티

| 프로퍼티 | 타입 | 설명 |
|---------|------|------|
| `dataStream` | `AsyncStream<BrainWaveData>` | EEG 데이터 스트림 |
| `stateStream` | `AsyncStream<ConnectionState>` | 연결 상태 스트림 |

### 메서드

| 메서드 | 설명 |
|--------|------|
| `connect(_ deviceAddress: String) async throws` | 이름 또는 UUID로 연결 |
| `disconnect() async` | 연결 해제 |
| `sendCommand(_ command: UInt8) async throws` | 헤드셋에 명령 전송 |
| `startRawEeg() async throws` | Raw EEG 수신 시작 |
| `stopRawEeg() async throws` | Raw EEG 수신 중지 |
| `setNotch50Hz() async throws` | 50Hz 노치 필터 (중국/유럽) |
| `setNotch60Hz() async throws` | 60Hz 노치 필터 (한국/미국) |

---

## BrainWaveData

`Sendable` struct. EEG 헤드셋 데이터 스냅샷.

| 필드 | 타입 | 범위 | 설명 |
|------|------|------|------|
| `timestamp` | `Int64` | Unix ms | 수신 시각 |
| `poorSignal` | `Int` | 0~200 | 0=완벽, 200=무신호 |
| `attention` | `Int` | 0~100 | 집중도 |
| `meditation` | `Int` | 0~100 | 명상도 |
| `delta` | `Int` | 0~ | 델타파 (0.5~2.75 Hz) |
| `theta` | `Int` | 0~ | 세타파 (3.5~6.75 Hz) |
| `lowAlpha` | `Int` | 0~ | 알파 저주파 (7.5~9.25 Hz) |
| `highAlpha` | `Int` | 0~ | 알파 고주파 (10~11.75 Hz) |
| `lowBeta` | `Int` | 0~ | 베타 저주파 (13~16.75 Hz) |
| `highBeta` | `Int` | 0~ | 베타 고주파 (18~29.75 Hz) |
| `lowGamma` | `Int` | 0~ | 감마 저주파 (31~39.75 Hz) |
| `midGamma` | `Int` | 0~ | 감마 중주파 (41~49.75 Hz) |
| `rawEeg` | `[Int]` | -32768~32767 | 패킷당 10샘플 (512 Hz) |
| `eyeBlink` | `Int` | 0~ | 눈 깜빡임 강도 |
| `signalQuality` | `SignalQuality` | — | 계산 프로퍼티 |

---

## SignalQuality

```swift
public enum SignalQuality {
    case noSignal  // poorSignal == 200
    case poor      // poorSignal > 50
    case fair      // poorSignal > 0
    case good      // poorSignal == 0
}
```

---

## ConnectionState

```swift
public enum ConnectionState {
    case disconnected
    case scanning
    case connecting
    case connected
    case error(Error)
}
```

---

## NeuroSkyCommand

| 상수 | 값 | 설명 |
|------|----|------|
| `startRawEeg` | `0x15` | Raw EEG 수신 시작 |
| `stopRawEeg` | `0x16` | Raw EEG 수신 중지 |
| `startEsense` | `0x17` | eSense 수신 시작 |
| `stopEsense` | `0x18` | eSense 수신 중지 |
| `notch50Hz` | `0x1B` | 50Hz 노치 필터 |
| `notch60Hz` | `0x1C` | 60Hz 노치 필터 |

---

## NeuroSkyUUID

| 상수 | UUID |
|------|------|
| `esense` | 039afff8-2c94-11e3-9e06-0002a5d5c51b |
| `handshake` | 039affa0-2c94-11e3-9e06-0002a5d5c51b |
| `rawEeg` | 039afff4-2c94-11e3-9e06-0002a5d5c51b |
| `spp` | 00001101-0000-1000-8000-00805f9b34fb |

---

## SimulatorTransport

실기기 없이 개발할 때 사용하는 Transport. Debug 빌드 전용 권장.

### 초기화

```swift
init(mode: SimulatorTransport.Mode = .random)
```

### 메서드

| 메서드 | 설명 |
|--------|------|
| `setMode(_ mode: Mode)` | 실행 중 모드 변경 (즉시 적용) |

> `NeuroSkySdk(simulator:)`로 초기화하면 내부적으로 SimulatorTransport가 사용됨.
> SimulatorTransport를 직접 사용할 경우 Transport 프로토콜을 통해 주입 가능.

### SimulatorTransport.Mode

| 모드 | attention | meditation | 설명 |
|------|-----------|------------|------|
| `.random` | 20~80 | 20~80 | 랜덤 값 (poorSignal 0~10) |
| `.focused` | 70~95 | 40~60 | 집중 상태 (poorSignal=0) |
| `.relaxed` | 20~45 | 70~95 | 이완 상태 (poorSignal=0) |
| `.poorSignal` | 0 | 0 | 무신호 (poorSignal=200) |

---

## ThinkGearParser

직접 사용이 필요한 경우를 위해 공개.

```swift
// eSense 패킷 파싱 (0xEA / 0xEB / 0xEC)
func parseEsense(_ data: Data) -> BrainWaveData?

// Raw EEG 파싱
func parseRawEeg(_ data: Data) -> BrainWaveData

// 핸드셰이크 패킷 생성 (static)
static func buildHandshake(command: UInt8) -> Data
```
