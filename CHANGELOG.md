# Changelog

## [Unreleased]

### Removed
- Bluetooth Classic transport (BLE-only from v7.0.0)

### Added
- eyeBlink parsing

## [7.0.0] - TBD

### Changed
- Version scheme realigned with the MindWave SDK line (legacy 4.x)
- README / developer guide install examples updated to `from: "7.0.0"`
- `LICENSE` replaced with the verbatim Apache License 2.0 text (the previous file was an abridged, non-standard rendition)

### Added
- `PrivacyInfo.xcprivacy` shipped with the SDK (no tracking, no data collection)
- BLE connect timeout — `connect(_:mode:timeout:)` throws `BLEError.deviceNotFound`
  if the scan + handshake does not finish within the supplied window (default 10 s)

### Fixed
- `connect()` no longer hangs when the peripheral disconnects mid-handshake
  (`didDisconnectPeripheral` now resumes the pending continuation with an error)

### Removed
- `BrainWaveData.eyeBlink` — the field was never populated by the parser and
  has been removed to keep the public API honest. Will be reintroduced when
  blink-strength packet parsing is implemented.

## [1.0.0] — 2026-04-06

### Added
- Swift Package Manager distribution (iOS 14+, macOS 11+)
- `BLETransport` — CoreBluetooth GATT implementation (iOS + macOS)
- `BTClassicTransport` — IOBluetooth RFCOMM SPP implementation (macOS only)
- `TransportMode` enum — explicit `.ble` (default) / `.btClassic` selection
- `findDeviceIdentifier(_:timeout:)` — scan for BLE peripheral by name, returns
  the OS-assigned `CBPeripheral.identifier` UUID string
- `SimulatorTransport` — synthetic data without a real headset;
  modes: `.random` / `.focused` / `.relaxed` / `.poorSignal`
- `ThinkGearParser` — decodes 0xEA / 0xEB / 0xEC eSense packets, Raw EEG
  sign-extension, and 20-byte handshake packet builder
- `AsyncStream<BrainWaveData>` data stream + `AsyncStream<ConnectionState>` state stream
- `@MainActor` on `NeuroSkySdk` for safe UI updates from async tasks
- `setNotch50Hz()` / `setNotch60Hz()` convenience commands
- `startRawEeg()` / `stopRawEeg()` convenience commands

### Removed
- Auto-fallback from BLE to BT Classic — use `mode: .btClassic` explicitly instead
