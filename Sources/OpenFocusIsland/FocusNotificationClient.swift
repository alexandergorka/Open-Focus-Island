import Foundation
import UserNotifications

enum FocusNotificationAuthorization: Sendable {
    case authorized
    case denied
    case notDetermined
}

@MainActor
protocol FocusNotificationClient: AnyObject {
    func authorizationStatus(_ completion: @escaping @MainActor @Sendable (FocusNotificationAuthorization) -> Void)
    func requestAuthorization(_ completion: @escaping @MainActor @Sendable (Bool, String?) -> Void)
    func schedule(identifier: String, title: String, body: String, at date: Date, completion: @escaping @MainActor @Sendable (String?) -> Void)
    func cancel(identifier: String)
}

@MainActor
final class SystemFocusNotificationClient: NSObject, FocusNotificationClient, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    static func makeRequest(identifier: String, title: String, body: String, at date: Date, now: Date) throws -> UNNotificationRequest {
        let remaining = date.timeIntervalSince(now)
        guard date.timeIntervalSince1970.isFinite, now.timeIntervalSince1970.isFinite, remaining.isFinite else {
            throw RequestError.invalidDate
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        return UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, remaining), repeats: false)
        )
    }

    func authorizationStatus(_ completion: @escaping @MainActor @Sendable (FocusNotificationAuthorization) -> Void) {
        center.getNotificationSettings { settings in
            let status: FocusNotificationAuthorization
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                status = .authorized
            case .denied:
                status = .denied
            default:
                status = .notDetermined
            }
            Task { @MainActor in completion(status) }
        }
    }

    func requestAuthorization(_ completion: @escaping @MainActor @Sendable (Bool, String?) -> Void) {
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            Task { @MainActor in completion(granted, error?.localizedDescription) }
        }
    }

    func schedule(identifier: String, title: String, body: String, at date: Date, completion: @escaping @MainActor @Sendable (String?) -> Void) {
        do {
            let request = try Self.makeRequest(identifier: identifier, title: title, body: body, at: date, now: Date())
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            center.add(request) { error in
                Task { @MainActor in completion(error?.localizedDescription) }
            }
        } catch {
            completion(error.localizedDescription)
        }
    }

    func cancel(identifier: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    private enum RequestError: LocalizedError {
        case invalidDate

        var errorDescription: String? { "Notification has an invalid date." }
    }
}
