/// NeuroSky MindWave BLE UUID 상수
public enum NeuroSkyUUID {
    public static let esense    = "039afff8-2c94-11e3-9e06-0002a5d5c51b"
    public static let handshake = "039affa0-2c94-11e3-9e06-0002a5d5c51b"
    public static let rawEeg    = "039afff4-2c94-11e3-9e06-0002a5d5c51b"
    public static let cccd      = "00002902-0000-1000-8000-00805f9b34fb"

    /// BT Classic SPP UUID
    public static let spp       = "00001101-0000-1000-8000-00805f9b34fb"
}

/// NeuroSky 헤드셋 명령 바이트
public enum NeuroSkyCommand {
    public static let startRawEeg: UInt8  = 0x15
    public static let stopRawEeg: UInt8   = 0x16
    public static let startEsense: UInt8  = 0x17
    public static let stopEsense: UInt8   = 0x18
    public static let notch50Hz: UInt8    = 0x1B  // 중국/유럽
    public static let notch60Hz: UInt8    = 0x1C  // 한국/미국
}
