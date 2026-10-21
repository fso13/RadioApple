import Foundation
import ServiceManagement

struct LaunchAtLoginResult {
    let ok: Bool
    let enabled: Bool
    let supported: Bool
    let error: String?
}

/// Thin wrapper around `SMAppService.mainApp` (macOS 13+).
enum LaunchAtLogin {
    static func status() -> LaunchAtLoginResult {
        let enabled = SMAppService.mainApp.status == .enabled
        return LaunchAtLoginResult(ok: true, enabled: enabled, supported: true, error: nil)
    }

    static func set(enabled: Bool) -> LaunchAtLoginResult {
        let service = SMAppService.mainApp
        do {
            if enabled {
                guard service.status != .enabled else {
                    return LaunchAtLoginResult(ok: true, enabled: true, supported: true, error: nil)
                }
                try service.register()
            } else {
                guard service.status != .notRegistered else {
                    return LaunchAtLoginResult(ok: true, enabled: false, supported: true, error: nil)
                }
                try service.unregister()
            }
            return LaunchAtLoginResult(
                ok: true,
                enabled: service.status == .enabled,
                supported: true,
                error: nil
            )
        } catch {
            return LaunchAtLoginResult(
                ok: false,
                enabled: service.status == .enabled,
                supported: true,
                error: error.localizedDescription
            )
        }
    }
}
