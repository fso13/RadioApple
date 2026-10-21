import Cocoa
import FlutterMacOS
import ServiceManagement

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)

    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      let messenger = controller.engine.binaryMessenger
      let channel = FlutterMethodChannel(
        name: "radio_mac/macos",
        binaryMessenger: messenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        self?.handleMethodCall(call: call, result: result)
      }
      RadioEngine.shared.setup(messenger: messenger)
    }

    super.applicationDidFinishLaunching(notification)
  }

  private func handleMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "activate":
      NSApp.activate(ignoringOtherApps: true)
      result(nil)
    case "getLaunchAtLogin":
      result(getLaunchAtLoginStatus())
    case "setLaunchAtLogin":
      if let enabled = call.arguments as? Bool {
        result(setLaunchAtLogin(enabled))
      } else if let args = call.arguments as? [String: Any],
                let enabled = args["enabled"] as? Bool {
        result(setLaunchAtLogin(enabled))
      } else {
        result(["ok": false, "error": "Invalid arguments"])
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func getLaunchAtLoginStatus() -> [String: Any] {
    if #available(macOS 13.0, *) {
      let status = SMAppService.mainApp.status
      return [
        "ok": true,
        "enabled": status == .enabled,
        "supported": true,
      ]
    }
    return [
      "ok": true,
      "enabled": false,
      "supported": false,
      "error": "Требуется macOS 13 или новее",
    ]
  }

  private func setLaunchAtLogin(_ enabled: Bool) -> [String: Any] {
    if #available(macOS 13.0, *) {
      do {
        if enabled {
          if SMAppService.mainApp.status == .enabled {
            return ["ok": true, "enabled": true, "supported": true]
          }
          try SMAppService.mainApp.register()
        } else {
          if SMAppService.mainApp.status == .notRegistered {
            return ["ok": true, "enabled": false, "supported": true]
          }
          try SMAppService.mainApp.unregister()
        }
        let nowEnabled = SMAppService.mainApp.status == .enabled
        return ["ok": true, "enabled": nowEnabled, "supported": true]
      } catch {
        return [
          "ok": false,
          "enabled": SMAppService.mainApp.status == .enabled,
          "supported": true,
          "error": error.localizedDescription,
        ]
      }
    }
    return [
      "ok": false,
      "enabled": false,
      "supported": false,
      "error": "Требуется macOS 13 или новее",
    ]
  }
}
