import Foundation

/// Detects eye blinks in the raw EEG stream.
///
/// A blink shows up as a short, large deflection in raw EEG. The detector keeps the most
/// recent `windowSize` samples (about 200 ms at 512 Hz) and reports a blink when their
/// peak-to-peak amplitude reaches `threshold`, at most once per `cooldownMs`.
/// For `warmupMs` after the stream starts (or resumes after a gap longer than
/// `restartGapMs`) detection is suppressed so settling transients are not counted.
/// Thresholds use the same units as `BrainWaveData.rawEeg`. The web tutorial's 600 is in
/// Web Bluetooth raw units (about 1/5 of native) and over-detects here; `defaultThreshold`
/// is provisional until measured on a device.
public final class BlinkDetector {

    /// Provisional threshold — the web tutorial value (600) converted to native units.
    /// Not for release until confirmed by on-device measurement
    /// (30 deliberate blinks + 1 minute without blinking).
    public static let defaultThreshold = 3_000

    /// A gap longer than this between samples is treated as a stream restart.
    public static let restartGapMs: Int64 = 1_000
    private static let minSamples = 8
    private static let never = Int64.min / 2

    public let windowSize: Int
    public let threshold: Int
    public let cooldownMs: Int64
    public let warmupMs: Int64

    private let clock: () -> Int64
    private var window: [Int]
    private var count = 0
    private var head = 0
    private var armedAt: Int64 = 0
    private var lastSampleAt: Int64 = 0
    private var lastBlinkAt: Int64 = BlinkDetector.never

    public init(
        windowSize: Int = 100,
        threshold: Int = BlinkDetector.defaultThreshold,
        cooldownMs: Int64 = 600,
        warmupMs: Int64 = 500,
        clock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }
    ) {
        precondition(windowSize >= BlinkDetector.minSamples, "windowSize must be >= \(BlinkDetector.minSamples)")
        self.windowSize = windowSize
        self.threshold = threshold
        self.cooldownMs = cooldownMs
        self.warmupMs = warmupMs
        self.clock = clock
        self.window = [Int](repeating: 0, count: windowSize)
    }

    /// Feeds new raw samples and checks for a blink.
    /// - Returns: The window's peak-to-peak amplitude if a blink was detected; otherwise 0.
    public func process(_ samples: [Int]) -> Int {
        guard !samples.isEmpty else { return 0 }
        let now = clock()
        if count == 0 || now - lastSampleAt > BlinkDetector.restartGapMs { arm(now) }
        lastSampleAt = now

        for s in samples {
            window[head] = s
            head = (head + 1) % windowSize
            if count < windowSize { count += 1 }
        }

        guard count >= BlinkDetector.minSamples,
              now - armedAt >= warmupMs,
              now - lastBlinkAt > cooldownMs else { return 0 }

        let filled = window[0..<count]
        let peakToPeak = filled.max()! - filled.min()!
        guard peakToPeak >= threshold else { return 0 }

        lastBlinkAt = now
        return peakToPeak
    }

    /// Clears the window. Warm-up restarts with the next sample.
    public func reset() {
        count = 0
        head = 0
    }

    private func arm(_ now: Int64) {
        reset()
        armedAt = now
        lastBlinkAt = BlinkDetector.never
    }
}
