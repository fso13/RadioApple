import Foundation

/// Ten-band equalizer state, pushed straight into BASS (no stream restart needed).
final class EqualizerService: ObservableObject {
    private let defaults: UserDefaults
    private let engine: RadioEngine
    private var persistWorkItem: DispatchWorkItem?

    @Published private(set) var enabled: Bool = false
    @Published private(set) var presetID: String = EqualizerCatalog.flatID
    @Published private(set) var gains: [Double] = Array(repeating: 0, count: EqualizerCatalog.bandCount)

    private var customGains: [Double] = Array(repeating: 0, count: EqualizerCatalog.bandCount)

    init(defaults: UserDefaults = .standard, engine: RadioEngine = .shared) {
        self.defaults = defaults
        self.engine = engine
        load()
    }

    var preset: EqualizerPreset { EqualizerCatalog.byID(presetID) }
    /// `false` when the bundled BASS_FX plugin could not be loaded.
    var isSupported: Bool { engine.isEqualizerAvailable }
    var isCustom: Bool { presetID == EqualizerCatalog.customID }

    // MARK: - Loading

    private func load() {
        enabled = defaults.boolLike(DefaultsKey.eqEnabled) ?? false
        presetID = defaults.string(forKey: DefaultsKey.eqPreset) ?? EqualizerCatalog.flatID

        if let stored = Self.readGains(defaults, key: DefaultsKey.eqGains) {
            gains = stored
        } else {
            gains = EqualizerCatalog.clampGains(EqualizerCatalog.byID(presetID).gains)
        }
        customGains = Self.readGains(defaults, key: DefaultsKey.eqCustomGains) ?? gains

        if presetID != EqualizerCatalog.customID {
            gains = EqualizerCatalog.clampGains(preset.gains)
        }

        pushToEngine()
    }

    // MARK: - Commands

    func setEnabled(_ value: Bool) {
        guard value != enabled, isSupported else { return }
        enabled = value
        engine.setEQEnabled(value)
        persistNow()
    }

    func applyPreset(_ id: String) {
        presetID = id
        if id == EqualizerCatalog.customID {
            gains = EqualizerCatalog.clampGains(customGains)
        } else {
            gains = EqualizerCatalog.clampGains(EqualizerCatalog.byID(id).gains)
        }
        engine.setEQGains(gains)
        persistNow()
    }

    func setBand(_ index: Int, value: Double) {
        guard gains.indices.contains(index) else { return }
        gains[index] = min(EqualizerCatalog.maxGain, max(EqualizerCatalog.minGain, value))
        presetID = EqualizerCatalog.customID
        customGains = gains
        engine.setEQGains(gains)
        schedulePersist()
    }

    func resetFlat() {
        applyPreset(EqualizerCatalog.flatID)
    }

    // MARK: - Engine / persistence

    private func pushToEngine() {
        engine.setEQEnabled(enabled)
        engine.setEQGains(gains)
    }

    private func schedulePersist() {
        persistWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.persistNow() }
        persistWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    private func persistNow() {
        persistWorkItem?.cancel()
        defaults.set(enabled, forKey: DefaultsKey.eqEnabled)
        defaults.set(presetID, forKey: DefaultsKey.eqPreset)
        defaults.set(gains, forKey: DefaultsKey.eqGains)
        defaults.set(customGains, forKey: DefaultsKey.eqCustomGains)
    }

    /// Gains were stored by Flutter as a JSON string; accept both shapes.
    private static func readGains(_ defaults: UserDefaults, key: String) -> [Double]? {
        if let values = defaults.array(forKey: key) as? [Double], !values.isEmpty {
            return EqualizerCatalog.clampGains(values)
        }
        if let raw = defaults.string(forKey: key), let data = raw.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([Double].self, from: data) {
            return EqualizerCatalog.clampGains(decoded)
        }
        return nil
    }
}
