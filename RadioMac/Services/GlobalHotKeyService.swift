import Carbon.HIToolbox
import Combine
import Foundation

/// Carbon global hotkeys. They work while the panel is hidden and do not need
/// Accessibility permission. Registration failures expose system conflicts.
@MainActor
final class GlobalHotKeyService: ObservableObject {
    @Published private(set) var playPause: HotKeyCombo
    @Published private(set) var nextStation: HotKeyCombo
    @Published private(set) var errorText: String = ""

    private let player: RadioPlayerService
    private let library: StationLibrary
    private let defaults: UserDefaults
    private var handlerRef: EventHandlerRef?
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var started = false

    private static let signature: OSType = 0x524D434B // RMCK
    private static let playPauseID: UInt32 = 1
    private static let nextID: UInt32 = 2

    init(
        player: RadioPlayerService,
        library: StationLibrary,
        defaults: UserDefaults = .standard
    ) {
        self.player = player
        self.library = library
        self.defaults = defaults
        playPause = HotKeyCombo.decode(
            defaults.string(forKey: DefaultsKey.globalHotKeyPlayPause),
            fallback: .defaultPlayPause
        )
        nextStation = HotKeyCombo.decode(
            defaults.string(forKey: DefaultsKey.globalHotKeyNext),
            fallback: .defaultNext
        )
    }

    func start() {
        guard !started else { return }
        started = true
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }
                let service = Unmanaged<GlobalHotKeyService>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                Task { @MainActor in
                    service.handle(id: hotKeyID.id)
                }
                return noErr
            },
            1,
            &eventType,
            pointer,
            &handlerRef
        )
        registerAll()
    }

    func stop() {
        for (_, ref) in refs {
            UnregisterEventHotKey(ref)
        }
        refs.removeAll()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
        handlerRef = nil
        started = false
    }

    func setPlayPause(_ combo: HotKeyCombo) {
        update(action: .playPause, combo: combo)
    }

    func setNext(_ combo: HotKeyCombo) {
        update(action: .nextStation, combo: combo)
    }

    private func update(action: HotKeyAction, combo: HotKeyCombo) {
        if let reason = combo.systemConflictReason {
            errorText = "\(combo.display): \(reason)"
            return
        }
        if action == .playPause, combo == nextStation {
            errorText = "Сочетание уже занято следующей станцией"
            return
        }
        if action == .nextStation, combo == playPause {
            errorText = "Сочетание уже занято play/pause"
            return
        }

        let previous = action == .playPause ? playPause : nextStation
        switch action {
        case .playPause: playPause = combo
        case .nextStation: nextStation = combo
        }
        if let message = register(action: action, combo: combo) {
            switch action {
            case .playPause: playPause = previous
            case .nextStation: nextStation = previous
            }
            errorText = message
            _ = register(action: action, combo: previous)
            return
        }
        errorText = ""
        defaults.set(combo.encoded, forKey: action == .playPause
            ? DefaultsKey.globalHotKeyPlayPause
            : DefaultsKey.globalHotKeyNext)
    }

    private func registerAll() {
        errorText = ""
        if let message = register(action: .playPause, combo: playPause) {
            errorText = message
        }
        if let message = register(action: .nextStation, combo: nextStation) {
            errorText = message
        }
    }

    private func register(action: HotKeyAction, combo: HotKeyCombo) -> String? {
        let id = action == .playPause ? Self.playPauseID : Self.nextID
        if let old = refs[id] {
            UnregisterEventHotKey(old)
            refs[id] = nil
        }
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(
            combo.key.rawValue,
            combo.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            return "\(combo.display) недоступно: конфликт с системным шорткатом"
        }
        refs[id] = ref
        return nil
    }

    private func handle(id: UInt32) {
        switch id {
        case Self.playPauseID:
            player.togglePlayPause()
        case Self.nextID:
            playNext()
        default:
            break
        }
    }

    private func playNext() {
        let stations = library.stations
        guard !stations.isEmpty else { return }
        if let current = player.station,
           let index = stations.firstIndex(where: { $0.id == current.id }) {
            player.play(stations[(index + 1) % stations.count])
        } else {
            player.play(stations[0])
        }
    }
}
