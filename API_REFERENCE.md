# API Reference — NeuroSky MindWave SDK (Apple)

---

## NeuroSkySdk

Main entry point. `@MainActor` class.

### Initializers

```swift
// Connect to a real headset
init()

// Simulator mode — no headset required
init(simulator mode: SimulatorTransport.Mode = .random)
```

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `dataStream` | `AsyncStream<BrainWaveData>` | EEG data stream |
| `stateStream` | `AsyncStream<ConnectionState>` | Connection state stream |

### Methods

| Method | Description |
|--------|-------------|
| `connect(_ deviceAddress: String, mode: TransportMode = .ble) async throws` | Connect by peripheral name or UUID string |
| `disconnect() async` | Disconnect and release all resources |
| `findDeviceIdentifier(_ deviceName: String, timeout: TimeInterval = 10) async -> String?` | Scan for a BLE peripheral by name, returns its UUID string |
| `sendCommand(_ command: UInt8) async throws` | Send a raw command byte to the headset |
| `startRawEeg() async throws` | Start Raw EEG streaming |
| `stopRawEeg() async throws` | Stop Raw EEG streaming |
| `setNotch50Hz() async throws` | Apply 50 Hz notch filter (China / Europe) |
| `setNotch60Hz() async throws` | Apply 60 Hz notch filter (Korea / USA) |

#### `connect(_:mode:)`

```swift
try await sdk.connect("MindWave Mobile")               // BLE by name (default)
try await sdk.connect(savedUUID)                        // BLE by UUID string
try await sdk.connect("MindWave Mobile", mode: .btClassic)  // BT Classic (macOS only)
```

#### `findDeviceIdentifier(_:timeout:)`

Scans for a BLE peripheral whose name contains `deviceName` (case-insensitive) and returns its `CBPeripheral.identifier` UUID string. Returns `nil` if no match is found within `timeout` seconds.

```swift
if let uuid = await sdk.findDeviceIdentifier("MindWave") {
    UserDefaults.standard.set(uuid, forKey: "deviceUUID")
    try await sdk.connect(uuid)
}
```

Cache the returned UUID to avoid scanning on every app launch.

---

## TransportMode

Selects which Bluetooth transport to use when calling `connect(_:mode:)`.

```swift
public enum TransportMode {
    case ble         // CoreBluetooth BLE. Default. iOS + macOS.
    case btClassic   // IOBluetooth RFCOMM SPP. macOS only. Requires pairing first.
}
```

---

## BrainWaveData

`Sendable` struct. Snapshot of EEG headset data.

| Field | Type | Range | Description |
|-------|------|-------|-------------|
| `timestamp` | `Int64` | Unix ms | Time of reception |
| `poorSignal` | `Int` | 0–200 | 0 = perfect contact, 200 = no signal |
| `attention` | `Int` | 0–100 | eSense attention level |
| `meditation` | `Int` | 0–100 | eSense meditation level |
| `delta` | `Int` | 0+ | Delta band power (0.5–2.75 Hz) |
| `theta` | `Int` | 0+ | Theta band power (3.5–6.75 Hz) |
| `lowAlpha` | `Int` | 0+ | Low alpha band power (7.5–9.25 Hz) |
| `highAlpha` | `Int` | 0+ | High alpha band power (10–11.75 Hz) |
| `lowBeta` | `Int` | 0+ | Low beta band power (13–16.75 Hz) |
| `highBeta` | `Int` | 0+ | High beta band power (18–29.75 Hz) |
| `lowGamma` | `Int` | 0+ | Low gamma band power (31–39.75 Hz) |
| `midGamma` | `Int` | 0+ | Mid gamma band power (41–49.75 Hz) |
| `rawEeg` | `[Int]` | −32768–32767 | 10 samples per packet at 512 Hz |
| `signalQuality` | `SignalQuality` | — | Computed from `poorSignal` |

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

## TransportError

```swift
public enum TransportError: Error {
    case btClassicNotAvailableOniOS  // BT Classic is macOS only
}
```

---

## NeuroSkyCommand

| Constant | Value | Description |
|----------|-------|-------------|
| `startRawEeg` | `0x15` | Start Raw EEG streaming |
| `stopRawEeg` | `0x16` | Stop Raw EEG streaming |
| `startEsense` | `0x17` | Start eSense streaming |
| `stopEsense` | `0x18` | Stop eSense streaming |
| `notch50Hz` | `0x1B` | 50 Hz notch filter |
| `notch60Hz` | `0x1C` | 60 Hz notch filter |

---

## NeuroSkyUUID

| Constant | UUID |
|----------|------|
| `esense` | 039afff8-2c94-11e3-9e06-0002a5d5c51b |
| `handshake` | 039affa0-2c94-11e3-9e06-0002a5d5c51b |
| `rawEeg` | 039afff4-2c94-11e3-9e06-0002a5d5c51b |
| `spp` | 00001101-0000-1000-8000-00805f9b34fb (BT Classic SPP) |

---

## SimulatorTransport

Transport for development without a real headset. Emits synthetic data once per second. Recommended for `#if DEBUG` blocks only.

Use via `NeuroSkySdk(simulator:)` — direct instantiation is also supported for custom injection.

### Initializer

```swift
init(mode: SimulatorTransport.Mode = .random)
```

### Methods

| Method | Description |
|--------|-------------|
| `setMode(_ mode: Mode)` | Change the simulation mode at runtime |

### SimulatorTransport.Mode

| Mode | `attention` | `meditation` | Description |
|------|-------------|--------------|-------------|
| `.random` | 20–80 | 20–80 | Random values, `poorSignal` 0–10 |
| `.focused` | 70–95 | 40–60 | Focused state, `poorSignal` = 0 |
| `.relaxed` | 20–45 | 70–95 | Relaxed state, `poorSignal` = 0 |
| `.poorSignal` | 0 | 0 | No signal, `poorSignal` = 200 |

---

## ThinkGearParser

Exposed publicly for advanced use cases (e.g. custom BT Classic parsing).

```swift
// Parse eSense characteristic data (0xEA / 0xEB / 0xEC packets)
func parseEsense(_ data: Data) -> BrainWaveData?

// Parse RawEEG characteristic data (10 signed samples per 20-byte packet)
func parseRawEeg(_ data: Data) -> BrainWaveData

// Build a 20-byte handshake packet for the given command byte
static func buildHandshake(command: UInt8) -> Data
```
