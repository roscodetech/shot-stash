import Foundation
import ShotStashCore
import UserNotifications

/// Posts "Copied to clipboard" with a Save action. No-op when running unbundled (swift run),
/// because UNUserNotificationCenter requires a bundle identifier and would crash.
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private static let category = "com.roscodetech.shotstash.capture"
    private static let saveAction = "save"
    private static let captureKey = "captureID"

    var onSaveRequested: ((UUID) -> Void)?
    private let available = Bundle.main.bundleIdentifier != nil

    func setup(saveTitle: String) {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        updateSaveTitle(saveTitle)
        center.requestAuthorization(options: [.alert]) { _, error in
            if let error { NSLog("ShotStash: notification auth error: \(error)") }
        }
    }

    /// Re-registers the category so the button reflects the current default folder.
    func updateSaveTitle(_ title: String) {
        guard available else { return }
        let action = UNNotificationAction(identifier: Self.saveAction, title: "Save to \(title)", options: [])
        let category = UNNotificationCategory(identifier: Self.category, actions: [action], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func notify(_ capture: ClipItem) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = "Copied to clipboard"
        content.body = capture.sizeLabel ?? ""
        content.categoryIdentifier = Self.category
        content.userInfo = [Self.captureKey: capture.id.uuidString]
        let request = UNNotificationRequest(identifier: capture.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { NSLog("ShotStash: notification failed: \(error)") }
        }
    }

    /// Confirms a save; no action button.
    func notifySaved(_ url: URL) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = "Saved to \(url.deletingLastPathComponent().lastPathComponent)"
        content.body = url.lastPathComponent
        let request = UNNotificationRequest(identifier: "saved-\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { NSLog("ShotStash: notification failed: \(error)") }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        defer { completionHandler() }
        guard response.actionIdentifier == Self.saveAction,
              let raw = response.notification.request.content.userInfo[Self.captureKey] as? String,
              let id = UUID(uuidString: raw)
        else { return }
        DispatchQueue.main.async { [weak self] in self?.onSaveRequested?(id) }
    }
}
