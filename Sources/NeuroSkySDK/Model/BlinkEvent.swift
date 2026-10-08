import Foundation

/// One eye blink, emitted on `NeuroSkySdk.blinkStream` each time a blink is detected.
public struct BlinkEvent: Sendable, Equatable {
    /// Detection time (Unix epoch ms).
    public let timestampMs: Int64
    /// Raw EEG peak-to-peak amplitude of the detection window (raw EEG units, at or above the threshold).
    public let strength: Int
    /// Blinks since the connection started, starting at 1. Resets on reconnect.
    public let sequence: Int

    public init(timestampMs: Int64, strength: Int, sequence: Int) {
        self.timestampMs = timestampMs
        self.strength = strength
        self.sequence = sequence
    }
}
