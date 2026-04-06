# NeuroSky MindWave Mobile Apple SDK

[![Swift](https://img.shields.io/badge/Swift-5.7+-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Platforms](https://img.shields.io/badge/platforms-iOS%2014%2B%20%7C%20macOS%2011%2B-lightgrey?logo=apple&logoColor=white)](https://github.com/nsk-bci/mindwave-sdk-apple)
[![SPM](https://img.shields.io/badge/Swift_Package_Manager-compatible-orange)](https://github.com/nsk-bci/mindwave-sdk-apple)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue)](LICENSE)

Modern Swift SDK for NeuroSky MindWave Mobile EEG headsets — BLE + BT Classic.

---

## Getting Started

> [!TIP]
> Before diving into the steps — read the [Developer Guide (PDF)](docs/developer-guide.pdf) first.
> It covers the full connection flow, BLE vs BT Classic internals, signal quality handling, packet timing, advanced patterns, and the complete API reference. Most integration questions are answered there.

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
    // BLE (default) — works on iOS and macOS without pairing
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

| Mode | API call | Platforms | Pairing required? |
|---|---|---|---|
| BLE (default) | `sdk.connect("MindWave Mobile")` | iOS + macOS | No |
| BT Classic | `sdk.connect("MindWave Mobile", mode: .btClassic)` | macOS only | Yes |

## Finding Your Device Identifier

CoreBluetooth does not expose MAC addresses. Use `findDeviceIdentifier` to
discover the OS-assigned UUID, then cache it for subsequent launches:

```swift
// First launch — scan and cache
if let uuid = await sdk.findDeviceIdentifier("MindWave Mobile") {
    UserDefaults.standard.set(uuid, forKey: "mindwave_uuid")
    try await sdk.connect(uuid)
}

// Subsequent launches — connect directly (much faster)
if let uuid = UserDefaults.standard.string(forKey: "mindwave_uuid") {
    try await sdk.connect(uuid)
}
```

## Working with dataStream

### Packet timing

| Source | Characteristic | Typical rate |
|---|---|---|
| eSense (attention, meditation, EEG bands) | `039afff8` | ~1 Hz |
| Raw EEG samples | `039afff4` | ~51 Hz (10 samples/packet × 512 Hz) |

Both characteristics share the same `dataStream`. When both are active, the
stream delivers a mix of packets at their respective rates.

### Common pitfall — filtering by `attention == 0`

```swift
// WRONG — silently drops every RawEEG packet (attention is always 0 in those)
for await data in sdk.dataStream {
    guard data.attention > 0 else { continue }  // ← drops ~98% of packets
    processRawEeg(data.rawEeg)
}

// CORRECT — check the field you actually care about
for await data in sdk.dataStream {
    if !data.rawEeg.isEmpty {
        processRawEeg(data.rawEeg)         // Raw EEG packet
    }
    if data.attention > 0 || data.meditation > 0 {
        updateUI(data)                     // eSense packet
    }
}
```

### Receiving only eSense data

```swift
try await sdk.connect("MindWave Mobile")  // startEsense sent automatically

for await data in sdk.dataStream where data.rawEeg.isEmpty {
    print("Attention: \(data.attention), Meditation: \(data.meditation)")
}
```

### Receiving only Raw EEG

```swift
try await sdk.connect("MindWave Mobile")
try await sdk.startRawEeg()

for await data in sdk.dataStream where !data.rawEeg.isEmpty {
    let samples = data.rawEeg  // 10 signed Int samples, 512 Hz
    processDSP(samples)
}
```

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
├── NeuroSkySdk.swift            Entry point (@MainActor, TransportMode selection)
├── NeuroSkyUUID.swift           UUID and command constants
├── Model/
│   └── BrainWaveData.swift      EEG data model
├── Parser/
│   └── ThinkGearParser.swift    ThinkGear packet parser
├── Transport/
│   ├── Transport.swift          Common protocol, ConnectionState, TransportMode
│   ├── BLETransport.swift       CoreBluetooth implementation (iOS + macOS)
│   └── BTClassicTransport.swift IOBluetooth implementation (macOS only)
└── Simulator/
    └── SimulatorTransport.swift Developer simulator
```

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for the full history.

## License

Apache License 2.0
