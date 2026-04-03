# NeuroSky MindWave SDK — Apple (iOS / macOS)

Swift Package Manager 기반 NeuroSky MindWave EEG 헤드셋 SDK.  
TGC(ThinkGear Connector) 없이 BLE 직접 연결, macOS는 BT Classic 폴백 지원.

---

## 요구 사항

| 플랫폼 | 최소 버전 | 연결 방식 |
|--------|----------|-----------|
| iOS    | 14.0+    | BLE 전용 |
| macOS  | 11.0+    | BLE 우선 → BT Classic 폴백 |

Swift 5.7+ / Xcode 14+

---

## 설치

### Swift Package Manager

**Xcode:** File → Add Package Dependencies → GitHub URL 입력

**Package.swift:**
```swift
dependencies: [
    .package(url: "https://github.com/<your-org>/neurosky-sdk-apple", from: "2.0.0")
]
```

> GitHub 배포 후 URL을 실제 저장소 주소로 교체하세요.

---

## 빠른 시작

> `NeuroSkySdk`는 `@MainActor` 클래스입니다. `Task {}` 또는 SwiftUI `.task {}` 안에서 사용하세요.

```swift
import NeuroSkySDK

let sdk = NeuroSkySdk()

Task {
    // BLE 우선 연결 (macOS: 5초 실패 시 BT Classic 자동 폴백)
    try await sdk.connect("MindWave Mobile")

    for await data in sdk.dataStream {
        print("Attention:  \(data.attention)")
        print("Meditation: \(data.meditation)")
        print("Signal:     \(data.signalQuality)")
    }
}
```

### Simulator 모드 (실기기 불필요)

```swift
let sdk = NeuroSkySdk(simulator: .focused)

Task {
    try await sdk.connect("sim")  // 주소 무시

    for await data in sdk.dataStream {
        print(data.attention)  // 70~95 범위 값
    }
}
```

---

## 권한 설정

### iOS — Info.plist

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>MindWave 헤드셋 연결에 블루투스가 필요합니다.</string>
```

### macOS — Info.plist + Entitlements

```xml
<!-- Info.plist -->
<key>NSBluetoothAlwaysUsageDescription</key>
<string>MindWave 헤드셋 연결에 블루투스가 필요합니다.</string>
```

```xml
<!-- App.entitlements (BT Classic 사용 시) -->
<key>com.apple.security.device.bluetooth</key>
<true/>
```

Sandbox 앱은 `com.apple.security.device.bluetooth` entitlement 필수.

---

## Raw EEG 수신

```swift
try await sdk.startRawEeg()

for await data in sdk.dataStream {
    // data.rawEeg: 패킷당 10샘플, 512 Hz
    print(data.rawEeg)
}

try await sdk.stopRawEeg()
```

---

## 노치 필터 설정

```swift
try await sdk.setNotch60Hz()  // 한국/미국 (기본값 권장)
try await sdk.setNotch50Hz()  // 중국/유럽
```

---

## 파일 구조

```
Sources/NeuroSkySDK/
├── NeuroSkySdk.swift           진입점 (BLE 폴백 로직 포함)
├── NeuroSkyUUID.swift          UUID / 명령 상수
├── Model/
│   └── BrainWaveData.swift     데이터 모델
├── Parser/
│   └── ThinkGearParser.swift   패킷 파서
├── Transport/
│   ├── Transport.swift         공통 프로토콜
│   ├── BLETransport.swift      CoreBluetooth (iOS + macOS)
│   └── BTClassicTransport.swift IOBluetooth (macOS only)
└── Simulator/
    └── SimulatorTransport.swift 개발용 시뮬레이터
```

---

## 라이선스

MIT
