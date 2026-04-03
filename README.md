# NeuroSky MindWave SDK — Apple (iOS / macOS)

Swift Package Manager SDK for NeuroSky MindWave EEG headsets.  
Direct BLE connection without ThinkGear Connector (TGC). macOS also supports BT Classic fallback.

---

## Requirements

| Platform | Minimum Version | Connection |
|----------|----------------|------------|
| iOS      | 14.0+          | BLE only |
| macOS    | 11.0+          | BLE first → BT Classic fallback |

Swift 5.7+ / Xcode 14+

---

## Installation

### Swift Package Manager

**Xcode:** File → Add Package Dependencies → enter the URL below

**Package.swift:**
```swift
dependencies: [
    .package(url: "https://github.com/nsk-bci/mindwave-sdk-apple", from: "1.0.0")
]
```

---

## Quick Start

> `NeuroSkySdk` is a `@MainActor` class. Use it inside `Task {}` or SwiftUI `.task {}`.

```swift
import NeuroSkySDK

let sdk = NeuroSkySdk()

Task {
    // BLE-first connection (macOS: auto-falls back to BT Classic after 5 s)
    try await sdk.connect("MindWave Mobile")

    for await data in sdk.dataStream {
        print("Attention:  \(data.attention)")
        print("Meditation: \(data.meditation)")
        print("Signal:     \(data.signalQuality)")
    }
}
```

### Simulator Mode (no hardware required)

```swift
let sdk = NeuroSkySdk(simulator: .focused)

Task {
    try await sdk.connect("sim")  // address is ignored

    for await data in sdk.dataStream {
        print(data.attention)  // values in the 70–95 range
    }
}
```

---

## Permissions

### iOS — Info.plist

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Bluetooth is required to connect to the MindWave headset.</string>
```

### macOS — Info.plist + Entitlements

```xml
<!-- Info.plist -->
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Bluetooth is required to connect to the MindWave headset.</string>
```

```xml
<!-- App.entitlements (required for BT Classic) -->
<key>com.apple.security.device.bluetooth</key>
<true/>
```

Sandboxed apps must include the `com.apple.security.device.bluetooth` entitlement.

---

## Raw EEG

```swift
try await sdk.startRawEeg()

for await data in sdk.dataStream {
    // data.rawEeg: 10 samples per packet at 512 Hz
    print(data.rawEeg)
}

try await sdk.stopRawEeg()
```

---

## Notch Filter

```swift
try await sdk.setNotch60Hz()  // Korea / USA (recommended default)
try await sdk.setNotch50Hz()  // China / Europe
```

---

## File Structure

```
Sources/NeuroSkySDK/
├── NeuroSkySdk.swift            Entry point (BLE fallback logic)
├── NeuroSkyUUID.swift           UUID and command constants
├── Model/
│   └── BrainWaveData.swift      Data model
├── Parser/
│   └── ThinkGearParser.swift    Packet parser
├── Transport/
│   ├── Transport.swift          Common protocol
│   ├── BLETransport.swift       CoreBluetooth (iOS + macOS)
│   └── BTClassicTransport.swift IOBluetooth (macOS only)
└── Simulator/
    └── SimulatorTransport.swift Developer simulator
```

---

## License

MIT
