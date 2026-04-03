# NeuroSky MindWave Mobile Apple SDK

[![CI](https://github.com/nsk-bci/mindwave-sdk-apple/actions/workflows/ci.yml/badge.svg)](https://github.com/nsk-bci/mindwave-sdk-apple/actions/workflows/ci.yml)
[![Swift](https://img.shields.io/badge/Swift-5.7+-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Platforms](https://img.shields.io/badge/platforms-iOS%2014%2B%20%7C%20macOS%2011%2B-lightgrey?logo=apple&logoColor=white)](https://github.com/nsk-bci/mindwave-sdk-apple)
[![SPM](https://img.shields.io/badge/Swift_Package_Manager-compatible-orange)](https://github.com/nsk-bci/mindwave-sdk-apple)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue)](LICENSE)

Modern Swift SDK for NeuroSky MindWave Mobile EEG headsets — BLE + BT Classic, no ThinkGear Connector required.

---

## Getting Started

### Step 1 — Add the package

**Xcode:** File → Add Package Dependencies → enter the URL below

**Package.swift:**
```swift
dependencies: [
    .package(url: "https://github.com/nsk-bci/mindwave-sdk-apple", from: "1.0.0")
],
targets: [
    .target(name: "MyApp", dependencies: ["NeuroSkySDK"])
]
```

### Step 2 — Declare Bluetooth permissions

**iOS — Info.plist**
```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Bluetooth is required to connect to the MindWave headset.</string>
```

**macOS — Info.plist + Entitlements**
```xml
<!-- Info.plist -->
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Bluetooth is required to connect to the MindWave headset.</string>

<!-- App.entitlements (required for BT Classic) -->
<key>com.apple.security.device.bluetooth</key>
<true/>
```

### Step 3 — Connect and stream

```swift
import NeuroSkySDK

// NeuroSkySdk is a @MainActor class — use inside Task{} or SwiftUI .task{}
let sdk = NeuroSkySdk()

Task {
    // BLE first; macOS auto-falls back to BT Classic after 5 sec
    try await sdk.connect("MindWave Mobile")

    // Set notch filter for your region (removes power-line noise)
    try await sdk.setNotch60Hz()  // Korea/USA
    // try await sdk.setNotch50Hz()  // Europe/China

    for await data in sdk.dataStream {
        print("Attention  : \(data.attention)")
        print("Meditation : \(data.meditation)")
        print("Signal     : \(data.signalQuality)")
    }
}
```

That's it — three steps from zero to streaming EEG data.

> **Need more detail?** See the full [Developer Guide](docs/developer-guide.pdf) for architecture, all connection modes, signal quality handling, advanced patterns, and the complete API reference.

---

## Requirements

| | Minimum |
|---|---|
| iOS | 14.0 |
| macOS | 11.0 |
| Swift | 5.7+ |
| Xcode | 14+ |
| Bluetooth | BLE adapter (BLE mode) or Classic BT adapter (BT Classic mode) |
| Device pairing | Not required for BLE; required for BT Classic |

## Connection Modes

| Mode | Behavior | Pairing required? |
|---|---|---|
| Auto (default) | BLE first; auto-falls back to BT Classic after 5 sec (macOS only) | No |
| BLE only | iOS and macOS — fastest, no pairing needed | No |
| BT Classic only | macOS only — more stable in noisy RF environments | Yes |

## Simulator (without a real device)

```swift
let sdk = NeuroSkySdk(simulator: .focused)

Task {
    try await sdk.connect("sim")  // address is ignored

    for await data in sdk.dataStream {
        print("Attention: \(data.attention)")  // 70–95 range
    }
}
```

| Mode | Attention | Meditation | Use case |
|---|---|---|---|
| `.random` | 0~100 (random) | 0~100 (random) | General testing |
| `.focused` | 70~95 | 40~60 | Focused state UI testing |
| `.relaxed` | 20~45 | 70~95 | Relaxed state UI testing |
| `.poorSignal` | 0 | 0 | Signal loss / error handling test |

## BrainWaveData

| Property | Type | Range | Description |
|---|---|---|---|
| `poorSignal` | `Int` | 0~200 | 0=perfect contact, 200=no signal |
| `attention` | `Int` | 0~100 | eSense attention level |
| `meditation` | `Int` | 0~100 | eSense meditation level |
| `delta` | `Int` | 0~∞ | 0.5~2.75 Hz |
| `theta` | `Int` | 0~∞ | 3.5~6.75 Hz |
| `lowAlpha` | `Int` | 0~∞ | 7.5~9.25 Hz |
| `highAlpha` | `Int` | 0~∞ | 10~11.75 Hz |
| `lowBeta` | `Int` | 0~∞ | 13~16.75 Hz |
| `highBeta` | `Int` | 0~∞ | 18~29.75 Hz |
| `lowGamma` | `Int` | 0~∞ | 31~39.75 Hz |
| `midGamma` | `Int` | 0~∞ | 41~49.75 Hz |
| `rawEeg` | `[Int]` | -32768~32767 | 512 Hz, 10 samples/packet |
| `signalQuality` | `SignalQuality` | enum | `.noSignal` / `.poor` / `.fair` / `.good` |

## Commands

```swift
// Notch filter — removes power-line noise (call after connecting)
try await sdk.setNotch60Hz()  // Korea/USA (60 Hz)
try await sdk.setNotch50Hz()  // China/Europe (50 Hz)

// Raw EEG stream (disabled by default)
try await sdk.startRawEeg()
try await sdk.stopRawEeg()
```

## Transport

| Transport | Method | Platforms |
|---|---|---|
| `BLETransport` | CoreBluetooth GATT | iOS 14+, macOS 11+ |
| `BTClassicTransport` | IOBluetooth RFCOMM SPP | macOS 11+ only |
| `SimulatorTransport` | Virtual data | iOS + macOS |

## Project Structure

```
Sources/NeuroSkySDK/
├── NeuroSkySdk.swift            Entry point (BLE first + BT Classic fallback)
├── NeuroSkyUUID.swift           UUID and command constants
├── Model/
│   └── BrainWaveData.swift      EEG data model
├── Parser/
│   └── ThinkGearParser.swift    ThinkGear packet parser
├── Transport/
│   ├── Transport.swift          Common protocol, ConnectionState enum
│   ├── BLETransport.swift       CoreBluetooth implementation (iOS + macOS)
│   └── BTClassicTransport.swift IOBluetooth implementation (macOS only)
└── Simulator/
    └── SimulatorTransport.swift Developer simulator
```

## Changelog

### v1.0.0
- CoreBluetooth BLE GATT implementation (iOS 14+ / macOS 11+)
- IOBluetooth BT Classic RFCOMM SPP implementation (macOS only)
- Auto-fallback: BLE → BT Classic (macOS, 5 sec timeout)
- `AsyncStream<BrainWaveData>` stream API — native Swift concurrency
- Simulator modes: `.random` / `.focused` / `.relaxed` / `.poorSignal`
- Swift 5.7, SPM distribution
- GitHub Actions CI: macOS build + test, iOS Simulator build

## License

Apache License 2.0
