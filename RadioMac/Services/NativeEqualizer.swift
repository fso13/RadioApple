import Foundation

/// Ten-band peaking equalizer processed inside the BASS DSP callback.
///
/// It replaces BASS_FX on machines where that plugin is unavailable (for
/// example macOS 27 / Apple Silicon, BASS_FX error 41). The stream is created
/// with `BASS_SAMPLE_FLOAT`, so the callback receives interleaved Float32.
final class NativeEqualizer: @unchecked Sendable {
    static let frequencies: [Float] = [
        32, 64, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000,
    ]

    private let lock = NSLock()
    private var enabled = false
    private var sampleRate: Double = 44_100
    private var channels = 2

    /// b0, b1, b2, a1, a2 for each band.
    private var coefficients = [Float](repeating: 0, count: 10 * 5)
    private var activeBands = [Bool](repeating: false, count: 10)
    private var z1 = [Float](repeating: 0, count: 10 * 8)
    private var z2 = [Float](repeating: 0, count: 10 * 8)

    func configure(
        enabled: Bool,
        gains: [Double],
        sampleRate: Int,
        channels: Int
    ) {
        lock.lock()
        defer { lock.unlock() }

        let rate = max(8_000, sampleRate)
        let channelCount = min(8, max(1, channels))
        if self.sampleRate != Double(rate) || self.channels != channelCount {
            self.sampleRate = Double(rate)
            self.channels = channelCount
            resetStates()
        }
        self.enabled = enabled

        for band in 0..<10 {
            let gain = band < gains.count ? Float(gains[band]) : 0
            let frequency = Self.frequencies[band]
            let offset = band * 5

            guard enabled,
                  abs(gain) >= 0.05,
                  Double(frequency) < self.sampleRate / 2
            else {
                activeBands[band] = false
                coefficients[offset] = 1
                coefficients[offset + 1] = 0
                coefficients[offset + 2] = 0
                coefficients[offset + 3] = 0
                coefficients[offset + 4] = 0
                continue
            }

            let a = pow(10, Double(gain) / 40)
            let w0 = 2 * Double.pi * Double(frequency) / self.sampleRate
            let alpha = sin(w0) / (2 * 0.9)
            let cosw0 = cos(w0)

            let b0 = 1 + alpha * a
            let b1 = -2 * cosw0
            let b2 = 1 - alpha * a
            let a0 = 1 + alpha / a
            let a1 = -2 * cosw0
            let a2 = 1 - alpha / a

            activeBands[band] = true
            coefficients[offset] = Float(b0 / a0)
            coefficients[offset + 1] = Float(b1 / a0)
            coefficients[offset + 2] = Float(b2 / a0)
            coefficients[offset + 3] = Float(a1 / a0)
            coefficients[offset + 4] = Float(a2 / a0)
        }
    }

    func setEnabled(_ value: Bool) {
        lock.lock()
        enabled = value
        if !value { resetStates() }
        lock.unlock()
    }

    /// Processes one interleaved Float32 buffer in place.
    func process(buffer: UnsafeMutableRawPointer, length: Int) {
        lock.lock()
        defer { lock.unlock() }

        guard enabled, channels > 0 else { return }
        let count = length / MemoryLayout<Float>.size
        guard count > channels else { return }

        let samples = buffer.bindMemory(to: Float.self, capacity: count)
        let frames = count / channels

        for frame in 0..<frames {
            let base = frame * channels
            for channel in 0..<channels {
                var value = samples[base + channel]
                for band in 0..<10 where activeBands[band] {
                    let offset = band * 5
                    let stateIndex = band * channels + channel
                    let output = coefficients[offset] * value + z1[stateIndex]
                    z1[stateIndex] = coefficients[offset + 1] * value
                        - coefficients[offset + 3] * output
                        + z2[stateIndex]
                    z2[stateIndex] = coefficients[offset + 2] * value
                        - coefficients[offset + 4] * output
                    value = output
                }
                samples[base + channel] = min(1, max(-1, value))
            }
        }
    }

    private func resetStates() {
        for index in z1.indices {
            z1[index] = 0
            z2[index] = 0
        }
    }
}
