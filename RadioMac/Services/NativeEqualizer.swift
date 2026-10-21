import AudioToolbox
import Foundation

/// Ten-band peaking equalizer for the AVPlayer audio tap.
///
/// The audio tap may hand us interleaved or planar Float32
/// Float32 (`AudioBufferList` with one buffer per channel), so both layouts are
/// supported without allocating in the real-time callback.
final class NativeEqualizer: @unchecked Sendable {
    static let frequencies: [Float] = [
        32, 64, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000,
    ]

    private let lock = NSLock()
    private var enabled = false
    private var gains = [Double](repeating: 0, count: 10)
    private var sampleRate: Double = 44_100
    private var channels = 2
    private var nonInterleaved = false
    private var formatKnown = false
    private var formatIsFloat = true

    /// b0, b1, b2, a1, a2 for each band.
    private var coefficients = [Float](repeating: 0, count: 10 * 5)
    private var activeBands = [Bool](repeating: false, count: 10)
    private var z1 = [Float](repeating: 0, count: 10 * 8)
    private var z2 = [Float](repeating: 0, count: 10 * 8)

    func configure(
        enabled: Bool,
        gains: [Double],
        sampleRate: Int,
        channels: Int,
        nonInterleaved: Bool = false
    ) {
        lock.lock()
        defer { lock.unlock() }
        self.enabled = enabled
        self.gains = normalized(gains)
        updateFormatLocked(
            sampleRate: sampleRate,
            channels: channels,
            nonInterleaved: nonInterleaved,
            isFloat: true
        )
    }

    func setEnabled(_ value: Bool) {
        lock.lock()
        enabled = value
        if !value { resetStates() }
        lock.unlock()
    }

    func setGains(_ values: [Double]) {
        lock.lock()
        gains = normalized(values)
        if formatKnown { recomputeLocked() }
        lock.unlock()
    }

    func setFormat(
        sampleRate: Int,
        channels: Int,
        nonInterleaved: Bool,
        isFloat: Bool
    ) {
        lock.lock()
        updateFormatLocked(
            sampleRate: sampleRate,
            channels: channels,
            nonInterleaved: nonInterleaved,
            isFloat: isFloat
        )
        lock.unlock()
    }

    // MARK: - Interleaved buffer

    func process(buffer: UnsafeMutableRawPointer, length: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard canProcess else { return }
        let count = length / MemoryLayout<Float>.size
        guard count > channels else { return }
        let samples = buffer.bindMemory(to: Float.self, capacity: count)
        processInterleaved(samples, frames: count / channels)
    }

    // MARK: - AVPlayer tap buffer list

    func process(bufferList: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard canProcess, frames > 0 else { return }

        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        if nonInterleaved {
            let channelCount = min(channels, buffers.count)
            for channel in 0..<channelCount {
                guard let data = buffers[channel].mData else { continue }
                let samples = data.assumingMemoryBound(to: Float.self)
                processChannel(samples, channel: channel, frames: frames)
            }
        } else {
            guard let data = buffers.first?.mData else { return }
            let samples = data.assumingMemoryBound(to: Float.self)
            processInterleaved(samples, frames: frames)
        }
    }

    // MARK: - Private

    private var canProcess: Bool {
        enabled && formatKnown && formatIsFloat && channels > 0
    }

    private func normalized(_ values: [Double]) -> [Double] {
        var result = [Double](repeating: 0, count: 10)
        for index in 0..<min(values.count, 10) {
            result[index] = min(12, max(-12, values[index]))
        }
        return result
    }

    private func updateFormatLocked(
        sampleRate: Int,
        channels: Int,
        nonInterleaved: Bool,
        isFloat: Bool
    ) {
        let rate = max(8_000, sampleRate)
        let channelCount = min(8, max(1, channels))
        let changed = !formatKnown
            || self.sampleRate != Double(rate)
            || self.channels != channelCount
            || self.nonInterleaved != nonInterleaved
            || formatIsFloat != isFloat
        self.sampleRate = Double(rate)
        self.channels = channelCount
        self.nonInterleaved = nonInterleaved
        formatIsFloat = isFloat
        formatKnown = true
        if changed { resetStates() }
        recomputeLocked()
    }

    private func recomputeLocked() {
        for band in 0..<10 {
            let gain = Float(gains[band])
            let frequency = Self.frequencies[band]
            let offset = band * 5

            guard enabled,
                  formatIsFloat,
                  abs(gain) >= 0.05,
                  Double(frequency) < sampleRate / 2
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
            let w0 = 2 * Double.pi * Double(frequency) / sampleRate
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

    private func processInterleaved(_ samples: UnsafeMutablePointer<Float>, frames: Int) {
        for frame in 0..<frames {
            let base = frame * channels
            for channel in 0..<channels {
                var value = samples[base + channel]
                for band in 0..<10 where activeBands[band] {
                    value = processBand(value, band: band, channel: channel)
                }
                samples[base + channel] = min(1, max(-1, value))
            }
        }
    }

    private func processChannel(
        _ samples: UnsafeMutablePointer<Float>,
        channel: Int,
        frames: Int
    ) {
        for frame in 0..<frames {
            var value = samples[frame]
            for band in 0..<10 where activeBands[band] {
                value = processBand(value, band: band, channel: channel)
            }
            samples[frame] = min(1, max(-1, value))
        }
    }

    private func processBand(_ value: Float, band: Int, channel: Int) -> Float {
        let offset = band * 5
        let stateIndex = band * channels + channel
        let output = coefficients[offset] * value + z1[stateIndex]
        z1[stateIndex] = coefficients[offset + 1] * value
            - coefficients[offset + 3] * output
            + z2[stateIndex]
        z2[stateIndex] = coefficients[offset + 2] * value
            - coefficients[offset + 4] * output
        return output
    }

    private func resetStates() {
        for index in z1.indices {
            z1[index] = 0
            z2[index] = 0
        }
    }
}
