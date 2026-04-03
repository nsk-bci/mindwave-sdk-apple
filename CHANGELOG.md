# Changelog

## [2.0.0] — 2026-04-02

### 추가
- Swift Package Manager 지원 (iOS 14+, macOS 11+)
- CoreBluetooth 기반 BLETransport (iOS + macOS 공용)
- IOBluetooth 기반 BTClassicTransport (macOS 전용)
- BLE 5초 타임아웃 → BT Classic 자동 폴백 (macOS)
- SimulatorTransport: RANDOM / FOCUSED / RELAXED / POOR_SIGNAL 모드
- ThinkGearParser: 0xEA/0xEB/0xEC 패킷, Raw EEG 부호처리, 핸드셰이크 생성
- AsyncStream 기반 dataStream / stateStream API
- `@MainActor` 적용으로 UI 업데이트 안전성 보장

