import AppKit
import ServiceManagement

// `ShotStash --launch-at-login on|off|status` toggles login-item registration and exits.
// Must be run from the installed bundle, e.g. /Applications/ShotStash.app/Contents/MacOS/ShotStash.
if let index = CommandLine.arguments.firstIndex(of: "--launch-at-login") {
    let value = index + 1 < CommandLine.arguments.count ? CommandLine.arguments[index + 1] : "status"
    let service = SMAppService.mainApp
    do {
        switch value {
        case "on": try service.register()
        case "off": try service.unregister()
        default: break
        }
        print("launch at login: \(service.status == .enabled ? "enabled" : "disabled")")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("launch at login failed: \(error)\n".utf8))
        exit(1)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
