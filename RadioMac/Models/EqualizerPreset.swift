import Foundation

/// A 10-band equalizer preset. Gains are in dB, ordered low → high:
/// 32, 64, 125, 250, 500, 1k, 2k, 4k, 8k, 16k Hz.
struct EqualizerPreset: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let gains: [Double]
}

enum EqualizerCatalog {
    static let bandCount = 10
    static let minGain = -12.0
    static let maxGain = 12.0
    static let frequencies: [Int] = [32, 64, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]

    static let customID = "custom"
    static let flatID = "flat"

    static let custom = EqualizerPreset(
        id: customID,
        label: "Свой",
        gains: Array(repeating: 0, count: bandCount)
    )

    static let presets: [EqualizerPreset] = [
        EqualizerPreset(id: flatID, label: "Плоский", gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        custom,
        EqualizerPreset(id: "bass", label: "Бас", gains: [8, 6, 4, 2, 0, -1, -2, -2, -2, -2]),
        EqualizerPreset(id: "treble", label: "Высокие", gains: [-3, -2, -1, 0, 1, 2, 4, 6, 7, 8]),
        EqualizerPreset(id: "voice", label: "Голос", gains: [-4, -3, -1, 2, 5, 5, 4, 1, -2, -4]),
        EqualizerPreset(id: "rock", label: "Рок", gains: [5, 4, 2, 0, -2, -1, 1, 3, 4, 5]),
        EqualizerPreset(id: "pop", label: "Поп", gains: [-1, 2, 4, 3, 0, -1, -1, 1, 3, 4]),
        EqualizerPreset(id: "jazz", label: "Джаз", gains: [3, 2, 0, 1, -2, -2, 0, 1, 3, 4]),
        EqualizerPreset(id: "electronic", label: "Электро", gains: [6, 5, 1, 0, -2, 2, 1, 2, 4, 6]),
        EqualizerPreset(id: "classical", label: "Классика", gains: [5, 3, 1, 0, 0, 0, -1, -1, 2, 4]),
        EqualizerPreset(id: "spoken", label: "Речь", gains: [-6, -4, 0, 3, 4, 4, 2, 0, -2, -5]),
    ]

    static func byID(_ id: String) -> EqualizerPreset {
        presets.first { $0.id == id } ?? presets[0]
    }

    static func label(forHz hz: Int) -> String {
        hz >= 1_000 ? "\(hz / 1_000)k" : "\(hz)"
    }

    /// Pads/truncates to `bandCount` bands and clamps every gain to ±12 dB.
    static func clampGains(_ raw: [Double]) -> [Double] {
        (0..<bandCount).map { index in
            let value = index < raw.count ? raw[index] : 0
            return min(maxGain, max(minGain, value))
        }
    }

    static func sameGains(_ lhs: [Double], _ rhs: [Double]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { abs($0 - $1) <= 0.05 }
    }
}
