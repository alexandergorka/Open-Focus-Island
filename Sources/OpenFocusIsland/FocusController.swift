import Combine
import FocusCore
import Foundation

@MainActor
final class FocusController: ObservableObject {
    @Published private(set) var settings = FocusSettings.defaults
    @Published private(set) var session = FocusSession()
    @Published private(set) var history: [FocusHistoryEntry] = []
    @Published private(set) var now: Date
    @Published private(set) var error: String?

    private let store: FocusStore
    private let clock: () -> Date
    private let notifications: (any FocusNotificationClient)?
    private let sounds: (any SessionSoundPlaying)?
    private var historyError: String?
    private var notificationRequestID = 0
    private var scheduledNotificationDates: [String: Date] = [:]

    init(store: FocusStore = FocusStore(), now: @escaping () -> Date = Date.init, notifications: (any FocusNotificationClient)? = nil, sounds: (any SessionSoundPlaying)? = nil) {
        self.store = store
        self.clock = now
        self.notifications = notifications
        self.sounds = sounds
        let currentTime = now()
        self.now = currentTime
        self.settings = store.loadSettings()
        let restoredSession = store.loadSession(at: currentTime)
        self.session = restoredSession
        loadHistory()
        recordCompletedFocus(restoredSession)
    }

    func start(kind: FocusSession.Kind, taskName: String? = nil) {
        let actionTime = tick()
        guard session.start(kind: kind, duration: settings.duration(for: kind), taskName: taskName, at: actionTime) else {
            error = settings.language.t("Session could not be started.", "Sitzung konnte nicht gestartet werden.")
            return
        }
        persistSession()
        syncNotification()
    }

    func pause() {
        let actionTime = tick()
        guard session.pause(at: actionTime) else { return }
        persistSession()
        syncNotification()
    }

    func resume() {
        let actionTime = tick()
        guard session.resume(at: actionTime) else { return }
        persistSession()
        syncNotification()
    }

    func finish() {
        let actionTime = tick()
        guard session.finish(at: actionTime) else { return }
        persistSession()
        syncNotification()
    }

    func skip() {
        let actionTime = tick()
        let completedNaturally = session.didFullyElapse
        let previousIdentifier = session.id.uuidString
        guard session.skipToBreak(
            shortDuration: settings.shortBreakDuration,
            longDuration: settings.longBreakDuration,
            at: actionTime
        ) else { return }
        if !completedNaturally { cancelNotification(identifier: previousIdentifier) }
        persistSession()
        syncNotification()
    }

    @discardableResult
    func tick() -> Date {
        let currentTime = clock()
        now = currentTime
        let targetEnd = session.targetEnd
        if session.reconcile(at: currentTime) {
            persistSession()
            recordCompletedFocus(session)
            syncNotification()
            if let targetEnd { playCompletionSound(for: session.kind, targetEnd: targetEnd, at: currentTime) }
        }
        return currentTime
    }

    @discardableResult
    func saveSettings(_ settings: FocusSettings) -> Bool {
        guard settings.isValid else {
            error = self.settings.language.t("Please enter values between 1 second and 24 hours for all durations.", "Bitte gib für alle Dauern Werte zwischen 1 Sekunde und 24 Stunden ein.")
            return false
        }
        do {
            let updated = FocusSettings(
                focusDuration: settings.focusDuration,
                shortBreakDuration: settings.shortBreakDuration,
                longBreakDuration: settings.longBreakDuration,
                notificationsEnabled: self.settings.notificationsEnabled,
                soundsEnabled: self.settings.soundsEnabled,
                notchModeEnabled: self.settings.notchModeEnabled,
                language: self.settings.language,
                menuBarTimerEnabled: self.settings.menuBarTimerEnabled
            )
            try store.saveSettings(updated)
            self.settings = updated
            error = historyError
            return true
        } catch {
            self.error = self.settings.language.t("Settings could not be saved: \(error.localizedDescription)", "Einstellungen konnten nicht gespeichert werden: \(error.localizedDescription)")
            return false
        }
    }

    func setNotchModeEnabled(_ enabled: Bool) {
        var updated = settings
        updated.notchModeEnabled = enabled
        do {
            try store.saveSettings(updated)
            settings = updated
            error = historyError
        } catch {
            self.error = settings.language.t("Notch mode could not be saved: \(error.localizedDescription)", "Notch-Modus konnte nicht gespeichert werden: \(error.localizedDescription)")
        }
    }

    func setLanguage(_ language: AppLanguage) {
        let changed = language != settings.language
        var updated = settings
        updated.language = language
        do {
            try store.saveSettings(updated)
            settings = updated
            error = historyError
            if changed, session.state == .running, settings.notificationsEnabled {
                cancelNotification(identifier: session.id.uuidString)
                syncNotification()
            }
        } catch {
            self.error = settings.language.t("Language could not be saved: \(error.localizedDescription)", "Sprache konnte nicht gespeichert werden: \(error.localizedDescription)")
        }
    }

    func setSoundsEnabled(_ enabled: Bool) {
        var updated = settings
        updated.soundsEnabled = enabled
        do {
            try store.saveSettings(updated)
            settings = updated
            error = historyError
        } catch {
            self.error = settings.language.t("Completion sounds could not be saved: \(error.localizedDescription)", "Abschlusstöne konnten nicht gespeichert werden: \(error.localizedDescription)")
        }
    }

    func setMenuBarTimerEnabled(_ enabled: Bool) {
        var updated = settings
        updated.menuBarTimerEnabled = enabled
        do {
            try store.saveSettings(updated)
            settings = updated
            error = historyError
        } catch {
            self.error = settings.language.t("Menu bar timer could not be saved: \(error.localizedDescription)", "Timer in der Menüleiste konnte nicht gespeichert werden: \(error.localizedDescription)")
        }
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        notificationRequestID += 1
        let requestID = notificationRequestID
        guard enabled else {
            _ = saveNotificationPreference(false)
            cancelScheduledNotifications()
            notifications?.cancel(identifier: session.id.uuidString)
            syncNotification()
            return
        }
        guard let notifications else {
            error = settings.language.t("Notifications are not available in this app.", "Benachrichtigungen sind in dieser App nicht verfügbar.")
            return
        }
        notifications.requestAuthorization { [weak self] granted, failure in
            guard let self, requestID == self.notificationRequestID else { return }
            guard granted else {
                _ = self.saveNotificationPreference(false)
                self.error = self.settings.language.t("Notifications were not allowed. \(failure ?? "Please check System Settings.")", "Benachrichtigungen wurden nicht erlaubt. \(failure ?? "Bitte prüfe die Systemeinstellungen.")")
                self.cancelScheduledNotifications()
                notifications.cancel(identifier: self.session.id.uuidString)
                self.syncNotification()
                return
            }
            guard self.saveNotificationPreference(true) else { return }
            self.syncNotification()
        }
    }

    func reconcileNotificationAuthorization() {
        guard let notifications else { return }
        guard settings.notificationsEnabled else {
            notifications.cancel(identifier: session.id.uuidString)
            return
        }
        let requestID = notificationRequestID
        notifications.authorizationStatus { [weak self] status in
            guard let self, requestID == self.notificationRequestID else { return }
            guard status == .authorized else {
                _ = self.saveNotificationPreference(false)
                self.error = status == .denied
                    ? self.settings.language.t("Notifications are disabled in System Settings.", "Benachrichtigungen sind in den Systemeinstellungen deaktiviert.")
                    : self.settings.language.t("Notifications have not been allowed yet. Enable them in Settings.", "Benachrichtigungen wurden noch nicht erlaubt. Aktiviere sie in den Einstellungen.")
                self.cancelScheduledNotifications()
                notifications.cancel(identifier: self.session.id.uuidString)
                self.syncNotification()
                return
            }
            if self.session.state == .running {
                self.syncNotification()
            } else if self.session.didFullyElapse {
                return
            } else {
                notifications.cancel(identifier: self.session.id.uuidString)
            }
        }
    }

    private func saveNotificationPreference(_ enabled: Bool) -> Bool {
        var updated = settings
        updated.notificationsEnabled = enabled
        do {
            try store.saveSettings(updated)
            settings = updated
            if enabled { error = historyError }
            return true
        } catch {
            self.error = settings.language.t("Notification setting could not be saved: \(error.localizedDescription)", "Einstellung für Benachrichtigungen konnte nicht gespeichert werden: \(error.localizedDescription)")
            return false
        }
    }

    private func syncNotification() {
        guard let notifications else { return }
        guard settings.notificationsEnabled else {
            cancelScheduledNotifications()
            notifications.cancel(identifier: session.id.uuidString)
            return
        }
        guard session.state == .running, let targetEnd = session.targetEnd else {
            if !session.didFullyElapse, scheduledNotificationDates[session.id.uuidString] != nil {
                cancelNotification(identifier: session.id.uuidString)
            }
            return
        }
        let desiredID = session.id.uuidString
        guard scheduledNotificationDates[desiredID] != targetEnd else { return }
        scheduledNotificationDates[desiredID] = targetEnd
        let title = session.kind == .focus
            ? settings.language.t("Focus complete", "Fokus abgeschlossen")
            : settings.language.t("Break complete", "Pause abgeschlossen")
        let body = session.taskName ?? settings.language.t("Your session has ended.", "Deine Sitzung ist beendet.")
        notifications.schedule(identifier: desiredID, title: title, body: body, at: targetEnd) { [weak self] failure in
            guard let self,
                  self.settings.notificationsEnabled,
                  self.session.state == .running,
                  self.session.id.uuidString == desiredID,
                  self.session.targetEnd == targetEnd,
                  self.scheduledNotificationDates[desiredID] == targetEnd,
                  let failure else { return }
            self.error = self.settings.language.t("Notification could not be scheduled: \(failure)", "Benachrichtigung konnte nicht geplant werden: \(failure)")
        }
    }

    private func cancelNotification(identifier: String) {
        scheduledNotificationDates.removeValue(forKey: identifier)
        notifications?.cancel(identifier: identifier)
    }

    private func cancelScheduledNotifications() {
        for identifier in scheduledNotificationDates.keys {
            notifications?.cancel(identifier: identifier)
        }
        scheduledNotificationDates.removeAll()
    }

    private func persistSession() {
        do {
            try store.saveSession(session)
            error = historyError
        } catch {
            self.error = settings.language.t("Session could not be saved: \(error.localizedDescription)", "Sitzung konnte nicht gespeichert werden: \(error.localizedDescription)")
        }
    }

    private func loadHistory() {
        do {
            history = try store.loadHistory()
        } catch {
            historyError = settings.language.t("History could not be loaded: \(error.localizedDescription)", "Verlauf konnte nicht geladen werden: \(error.localizedDescription)")
            self.error = historyError
        }
    }

    private func recordCompletedFocus(_ completedSession: FocusSession) {
        guard let entry = FocusHistoryEntry(session: completedSession) else { return }
        do {
            try store.recordCompletedFocus(completedSession)
            history.removeAll { $0.id == entry.id }
            history.insert(entry, at: 0)
            if self.error == historyError {
                historyError = nil
                self.error = nil
            }
        } catch {
            historyError = settings.language.t("Focus could not be saved to history: \(error.localizedDescription)", "Fokus konnte nicht im Verlauf gespeichert werden: \(error.localizedDescription)")
            self.error = historyError
        }
    }

    private func playCompletionSound(for kind: FocusSession.Kind, targetEnd: Date, at currentTime: Date) {
        guard settings.soundsEnabled, !settings.notificationsEnabled,
              currentTime.timeIntervalSince(targetEnd) <= 5 else { return }
        do {
            try sounds?.play(kind == .focus ? .focusCompleted : .breakCompleted, enabled: true)
        } catch {
            self.error = settings.language.t("Completion sound could not be played: \(error.localizedDescription)", "Abschlusston konnte nicht abgespielt werden: \(error.localizedDescription)")
        }
    }
}
