# Changelog

All notable changes to the NeuroSky MindWave Mobile Apple SDK are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

v7.0.0 continues the MindWave SDK line (legacy 4.x), rebuilt from scratch for the BLE-only MindWave Mobile 2.
Releases before 7.0.0 are documented in the [legacy changelog (v1.0.0)](https://github.com/nsk-bci/mindwave-sdk-apple/blob/v1.0.0/CHANGELOG.md).

## [Unreleased]

### Removed
- Bluetooth Classic transport (BLE-only from v7.0.0)

### Added
- eyeBlink parsing

## [7.0.0] - TBD

First release of the renewed MindWave SDK line for iOS and macOS.

> SPM users pinned to `from: "1.0.0"` will not receive v7.0.0 automatically.
> Update your dependency to `from: "7.0.0"`.

### Added
- Swift Package Manager distribution (iOS 14+, macOS 11+)
- `NeuroSkySdk` (`@MainActor`) with `AsyncStream<BrainWaveData>` data and `AsyncStream<ConnectionState>` state streams
- `findDeviceIdentifier(_:timeout:)` to look up a peripheral identifier by name
- BLE transport (CoreBluetooth, iOS + macOS) with a connect timeout: `connect(_:mode:timeout:)` throws `BLEError.deviceNotFound` (default 10 s)
- Bluetooth Classic (RFCOMM SPP) transport on macOS, selected explicitly with `mode: .btClassic` (no automatic fallback)
- `ThinkGearParser` for BLE eSense (`0xEA`/`0xEB`/`0xEC`) and Raw EEG packets
- Convenience commands: `setNotch50Hz()` / `setNotch60Hz()`, `startRawEeg()` / `stopRawEeg()`
- `SimulatorTransport` (`.random` / `.focused` / `.relaxed` / `.poorSignal`) for development without a headset
- `PrivacyInfo.xcprivacy` (no tracking, no data collection)
- `NOTICE`

### Changed
- Version scheme realigned with the MindWave SDK line (legacy 4.x)
- `LICENSE` replaced with the verbatim Apache License 2.0 text

### Fixed
- `connect()` no longer hangs when the peripheral disconnects mid-handshake

### Removed
- `BrainWaveData.eyeBlink`: it was never populated. It returns with eyeBlink parsing (see Unreleased)
- Developer guide PDFs: superseded by [`docs/developer-guide.md`](docs/developer-guide.md)
