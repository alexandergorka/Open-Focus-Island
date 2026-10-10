import AppKit
import Combine
import SwiftUI

@MainActor
final class FocusHistoryWindow: NSWindow {
    private var settingsObservation: AnyCancellable?

    init(controller: FocusController) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
                   styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        contentView = NSHostingView(rootView: FocusHistoryView(controller: controller))
        settingsObservation = controller.$settings.sink { [weak self] settings in
            self?.title = settings.language.t("History", "Verlauf")
        }
        center()
    }
}

private struct FocusHistoryView: View {
    @ObservedObject var controller: FocusController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ControllerError(controller: controller)
                if controller.history.isEmpty, controller.error == nil {
                    Text(controller.settings.language.t("No completed focus sessions yet.", "Noch keine abgeschlossenen Fokuszeiten."))
                        .foregroundStyle(.secondary)
                }
                ForEach(controller.history) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.taskName ?? controller.settings.language.t("Focus", "Fokus"))
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(historyDetail(entry, language: controller.settings.language))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .frame(minWidth: 360, maxWidth: .infinity, minHeight: 260, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
