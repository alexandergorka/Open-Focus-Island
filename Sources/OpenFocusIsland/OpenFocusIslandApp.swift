import AppKit
import Combine
import CoreGraphics
import FocusCore
import SwiftUI

@main
struct OpenFocusIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarControls(controller: appDelegate.controller, onShowHistory: { appDelegate.showHistory() })
        } label: {
            MenuBarLabel(controller: appDelegate.controller)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var controller: FocusController

    var body: some View {
        let session = controller.session
        HStack(spacing: 4) {
            Image(nsImage: menuBarSymbol)
            if controller.settings.menuBarTimerEnabled, session.state == .running || session.state == .paused {
                Text(timerText(session, now: controller.now)).monospacedDigit()
            }
        }
        .accessibilityLabel("Open Focus Island")
    }
}

/// Template version of the app icon's open focus ring with its center dot.
private let menuBarSymbol: NSImage = {
    let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
        let center = NSPoint(x: 9, y: 9)
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: 6.5, startAngle: 90, endAngle: 180, clockwise: true)
        arc.lineWidth = 2
        arc.lineCapStyle = .round
        NSColor.black.setStroke()
        arc.stroke()
        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: 7.25, y: 7.25, width: 3.5, height: 3.5)).fill()
        return true
    }
    image.isTemplate = true
    return image
}()

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller: FocusController
    private(set) var panel: FocusPanel?
    private var historyWindow: FocusHistoryWindow?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var sessionStateObserver: AnyCancellable?
    private var wasAwaitingAcknowledgement = false

    override init() {
        controller = FocusController(notifications: SystemFocusNotificationClient(), sounds: SessionSoundPlayer())
        super.init()
    }

    init(controller: FocusController) {
        self.controller = controller
        super.init()
    }

    @discardableResult
    func showHistory() -> FocusHistoryWindow {
        let window = historyWindow ?? FocusHistoryWindow(controller: controller)
        historyWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        return window
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let panel = FocusPanel(controller: controller)
        self.panel = panel
        panel.hidesWhenIdle = true
        panel.startMousePassThrough()
        // @Published sendet synchron auf dem Main-Thread; `state` ist bereits der neue Wert.
        sessionStateObserver = Publishers.CombineLatest(controller.$session.map(\.state), controller.$awaitingAcknowledgement)
            .removeDuplicates { $0 == $1 }
            .sink { [weak self, weak panel] state, awaiting in
            MainActor.assumeIsolated {
                guard let self, let panel else { return }
                // Offene Bestätigung klappt die Karte auf, nach der Bestätigung wieder ein.
                if awaiting != nil { panel.openControls() } else if self.wasAwaitingAcknowledgement { while panel.presentation != .compact { panel.setExpanded(false) } }
                self.wasAwaitingAcknowledgement = awaiting != nil
                panel.updateVisibility(for: state, acknowledgementPending: awaiting != nil)
            }
        }
        controller.reconcileNotificationAuthorization()

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append(workspaceCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })
        observers.append(workspaceCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })

        let timer = Timer(timeInterval: 1, repeats: true) { [weak controller] _ in
            Task { @MainActor [weak self] in
                controller?.tick()
                self?.panel?.refreshPosition()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func refresh() {
        controller.tick()
        panel?.refreshPosition()
    }
}

@MainActor
final class FocusPanel: NSPanel {
    private let controller: FocusController
    private let metrics: FocusPanelMetrics
    private let screenFrameOverride: CGRect?
    private let screenIDOverride: UInt32?
    private let applicationScreen: @MainActor () -> NSScreen?
    private var position = PanelPosition()
    private var notchGeometry: NotchGeometry?
    private var isDetached = false
    private var contentSize: CGSize
    static let animationDuration = 0.28
    private let reduceMotion: @MainActor () -> Bool
    private var resizeCompletion: DispatchWorkItem?
    private var resizeTarget: NSRect?
    private var dragLastScreenPoint: NSPoint?
    private var dragPointerOffset = NSPoint.zero
    private var mouseMonitors: [Any] = []

    init(controller: FocusController, screenFrame: CGRect? = nil, screenID: UInt32? = nil,
         applicationScreen: @escaping @MainActor () -> NSScreen? = activeApplicationScreen,
         reduceMotion: @escaping @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }) {
        self.reduceMotion = reduceMotion
        self.controller = controller
        screenFrameOverride = screenFrame
        screenIDOverride = screenID
        self.applicationScreen = applicationScreen
        let initialScreen = applicationScreen()
        notchGeometry = screenFrame == nil && controller.settings.notchModeEnabled ? Self.notchGeometry(for: initialScreen) : nil
        let initialSize = Self.compactSize(notchGeometry: notchGeometry)
        contentSize = initialSize
        metrics = FocusPanelMetrics(viewportSize: initialSize, notchGeometry: notchGeometry)
        let frame = screenFrame.map { Self.frame(size: initialSize, in: $0) } ?? Self.frame(size: initialSize, on: initialScreen, notchGeometry: notchGeometry)
        position.updateDisplay(id: screenID ?? (initialScreen?.displayID ?? 0))
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        title = "Open Focus Island"
        hidesOnDeactivate = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        let hostingView = NSHostingView(rootView: FocusPanelRoot(
            controller: controller,
            metrics: metrics,
            onDrag: { [weak self] delta in self?.drag(by: delta) },
            onExpanded: { [weak self] expanded in self?.setExpanded(expanded) },
            onControls: { [weak self] in self?.openControls() },
            onNotchModeChanged: { [weak self] in self?.updateNotchMode() },
            onContentSize: { [weak self] size in
                guard let self, !self.metrics.isExpanded else { return }
                self.updateContentSize(size)
            },
            onExpandedContentSize: { [weak self] size in
                guard let self else { return }
                let bridgeHeight = self.notchGeometry.map { $0.cutoutFrame.height - 10 } ?? 0
                self.updateExpandedContentSize(CGSize(width: size.width, height: size.height + bridgeHeight))
            },
            onTimerContentSize: { [weak self] size in
                guard let self, self.metrics.presentation == .timer else { return }
                self.updateContentSize(size, animated: true)
            }
        ))
        hostingView.sizingOptions = [] // The panel owns its canvas size, including during transitions.
        contentView = hostingView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            let point = event.locationInWindow
            if let handle = contentView?.hitTest(point), handle.identifier?.rawValue == "panel-drag-handle" {
                let screenPoint = convertPoint(toScreen: point)
                let center = convertPoint(toScreen: handle.convert(NSPoint(x: handle.bounds.midX, y: handle.bounds.midY), to: nil))
                dragLastScreenPoint = screenPoint
                dragPointerOffset = NSPoint(x: screenPoint.x - center.x, y: screenPoint.y - center.y)
            }
            super.sendEvent(event)
        case .leftMouseDragged:
            if let previous = dragLastScreenPoint {
                let point = convertPoint(toScreen: event.locationInWindow)
                dragLastScreenPoint = point
                drag(by: CGSize(width: point.x - previous.x, height: point.y - previous.y), pointer: point)
            } else { super.sendEvent(event) }
        case .leftMouseUp:
            dragLastScreenPoint = nil
            dragPointerOffset = .zero
            super.sendEvent(event)
        default:
            super.sendEvent(event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        if controller.awaitingAcknowledgement != nil { return controller.acknowledgeCompletion() }
        guard metrics.isExpanded else { return }
        setExpanded(false)
    }

    var presentation: PanelPresentation { metrics.presentation }

    /// Der WindowServer reicht Klicks auf SwiftUI-gerenderte Flächen transparenter Fenster an das Fenster darunter
    /// weiter. Deshalb nimmt die Insel Klicks explizit an, solange der Zeiger über ihrer sichtbaren Fläche ist;
    /// daneben (Rand der kompakten Leiste ohne Notch) bleibt sie durchlässig.
    func startMousePassThrough() {
        acceptsMouseMovedEvents = true
        updateMousePassThrough()
        mouseMonitors = [
            NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateMousePassThrough() }
            },
            NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
                MainActor.assumeIsolated { self?.updateMousePassThrough() }
                return event
            },
        ].compactMap { $0 }
    }

    func updateMousePassThrough(mouse: NSPoint = NSEvent.mouseLocation) {
        guard metrics.presentation == .compact, notchGeometry == nil, let handle = dragHandle(in: contentView) else {
            ignoresMouseEvents = false
            return
        }
        // Die kompakte Leiste ist zentriert und beginnt am Drag-Punkt; oben 8 pt Abstand, 48 pt hoch.
        let pillMinX = handle.convert(handle.bounds, to: nil).minX
        let pill = NSRect(x: frame.minX + pillMinX, y: frame.maxY - 8 - 48, width: frame.width - 2 * pillMinX, height: 48)
        ignoresMouseEvents = !pill.contains(mouse)
    }

    /// Zugeklappt und ohne laufende/pausierte Sitzung bleibt die Insel ausgeblendet; gestartet wird über die Menüleiste.
    var hidesWhenIdle = false

    func updateVisibility(for state: FocusSession.State? = nil, acknowledgementPending: Bool? = nil) {
        let state = state ?? controller.session.state
        let pending = acknowledgementPending ?? (controller.awaitingAcknowledgement != nil)
        guard hidesWhenIdle, !pending, !metrics.isExpanded, state != .running, state != .paused else { return orderFrontRegardless() }
        orderOut(nil)
    }

    // Kein withAnimation um setFrame: sonst animiert NSHostingView das Fenster selbst (updateAnimatedWindowSize) und kämpft gegen uns.
    func openControls() {
        metrics.presentation.openControls()
        updateContentSize(metrics.expandedContentSize, animated: true)
        makeKeyAndOrderFront(nil)
    }

    func setExpanded(_ expanded: Bool) {
        var presentation = metrics.presentation
        if expanded {
            presentation.expand(isNotched: notchGeometry != nil)
        } else {
            presentation.collapse(isNotched: notchGeometry != nil)
        }
        guard presentation != metrics.presentation else { return }
        withAnimation(reduceMotion() ? nil : .easeInOut(duration: Self.animationDuration)) {
            metrics.presentation = presentation
            let size: CGSize
            switch presentation {
            case .compact: size = Self.compactSize(notchGeometry: notchGeometry)
            case .timer: size = CGSize(width: 360, height: (notchGeometry?.cutoutFrame.height ?? 0) + 160)
            case .controls: size = metrics.expandedContentSize
            }
            updateContentSize(size, animated: true)
        }
        if presentation == .compact { updateVisibility() } else { makeKeyAndOrderFront(nil) }
    }

    private func updateNotchMode() {
        let screen = applicationScreen() ?? NSScreen.main ?? NSScreen.screens.first
        position = PanelPosition()
        position.updateDisplay(id: screenIDOverride ?? screen?.displayID ?? 0)
        isDetached = false
        notchGeometry = screenFrameOverride == nil && controller.settings.notchModeEnabled ? Self.notchGeometry(for: screen) : nil
        metrics.notchGeometry = notchGeometry
        if metrics.presentation == .timer && notchGeometry == nil { metrics.presentation = .controls }
        let size: CGSize
        switch metrics.presentation {
        case .compact: size = Self.compactSize(notchGeometry: notchGeometry)
        case .timer: size = CGSize(width: 360, height: (notchGeometry?.cutoutFrame.height ?? 0) + 160)
        case .controls: size = metrics.expandedContentSize
        }
        updateContentSize(size)
    }

    func updateExpandedContentSize(_ size: CGSize) {
        guard metrics.presentation == .controls, size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 64 else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.metrics.presentation == .controls, size != self.metrics.expandedContentSize else { return }
            self.metrics.expandedContentSize = size
            self.updateContentSize(size, animated: true)
        }
    }

    func updateContentSize(_ size: CGSize, animated: Bool = false) {
        contentSize = size
        let newFrame = positionedFrame(size: size, screenFrame: nil)
        guard newFrame != resizeTarget, newFrame != frame || metrics.viewportSize != newFrame.size else { return }
        resizeCompletion?.cancel()
        resizeCompletion = nil
        resizeTarget = nil
        guard animated, isVisible, !reduceMotion() else {
            setFrame(newFrame, display: true, animate: false)
            metrics.viewportSize = newFrame.size
            return
        }
        // Keep the outgoing surface inside the transparent window until SwiftUI finishes shrinking it.
        let canvasSize = CGSize(width: max(frame.width, newFrame.width), height: max(frame.height, newFrame.height))
        setFrame(NSRect(x: newFrame.midX - canvasSize.width / 2, y: newFrame.maxY - canvasSize.height,
                        width: canvasSize.width, height: canvasSize.height), display: true, animate: false)
        resizeTarget = newFrame
        withAnimation(.easeInOut(duration: Self.animationDuration)) {
            metrics.viewportSize = newFrame.size
        }
        let completion = DispatchWorkItem { [weak self] in self?.finishResize() }
        resizeCompletion = completion
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.animationDuration, execute: completion)
    }

    private func finishResize() {
        resizeCompletion?.cancel()
        resizeCompletion = nil
        if let resizeTarget { setFrame(resizeTarget, display: true, animate: false) }
        resizeTarget = nil
    }

    func refreshPosition(screenFrame: CGRect? = nil) {
        let newFrame = positionedFrame(size: contentSize, screenFrame: screenFrame)
        guard newFrame != resizeTarget else { return }
        finishResize()
        setFrame(newFrame, display: true, animate: false)
        metrics.viewportSize = newFrame.size
    }

    private func drag(by delta: CGSize, pointer: NSPoint? = nil) {
        finishResize()
        let activeScreen = applicationScreen() ?? NSScreen.main ?? NSScreen.screens.first
        let bounds = screenFrameOverride ?? activeScreen?.visibleFrame ?? frame
        if notchGeometry != nil {
            isDetached = true
            notchGeometry = nil
            metrics.notchGeometry = nil
            metrics.presentation = .compact
            contentSize = CGSize(width: 360, height: 64)
            metrics.viewportSize = contentSize
            let moved = PanelPosition.draggedFrame(from: frame, by: delta, within: bounds)
            guard !moved.isEmpty else { return }
            setFrame(moved, display: true, animate: false)
            contentView?.layoutSubtreeIfNeeded()
            if let pointer, let handle = dragHandle(in: contentView) {
                let center = convertPoint(toScreen: handle.convert(NSPoint(x: handle.bounds.midX, y: handle.bounds.midY), to: nil))
                let aligned = PanelPosition.draggedFrame(from: frame, by: CGSize(width: pointer.x - dragPointerOffset.x - center.x,
                                                                                   height: pointer.y - dragPointerOffset.y - center.y), within: bounds)
                if !aligned.isEmpty { setFrame(aligned, display: true, animate: false) }
            }
            position.setManualFrame(frame)
            return
        }
        let moved = PanelPosition.draggedFrame(from: frame, by: delta, within: bounds)
        guard !moved.isEmpty else { return }
        setFrame(moved, display: true, animate: false)
        position.setManualFrame(moved)
    }

    private func dragHandle(in view: NSView?) -> NSView? {
        guard let view else { return nil }
        if view.identifier?.rawValue == "panel-drag-handle" { return view }
        return view.subviews.lazy.compactMap { self.dragHandle(in: $0) }.first
    }

    private func positionedFrame(size: CGSize, screenFrame: CGRect?) -> NSRect {
        let screen = applicationScreen() ?? NSScreen.main ?? NSScreen.screens.first
        var resolvedSize = size
        let defaultFrame: CGRect
        if let boundsOverride = screenFrame ?? screenFrameOverride {
            defaultFrame = Self.frame(size: size, in: boundsOverride)
            position.updateDisplay(id: screenIDOverride ?? 0)
        } else if let screen {
            let activeNotch = controller.settings.notchModeEnabled ? Self.notchGeometry(for: screen) : nil
            if let id = screen.displayID {
                let changedDisplay = position.displayID != id
                position.updateDisplay(id: id)
                if changedDisplay {
                    isDetached = false
                    notchGeometry = activeNotch
                    metrics.notchGeometry = activeNotch
                    metrics.presentation = .compact
                    resolvedSize = Self.compactSize(notchGeometry: activeNotch)
                    contentSize = resolvedSize
                    metrics.viewportSize = resolvedSize
                } else if !isDetached, notchGeometry != activeNotch {
                    notchGeometry = activeNotch
                    metrics.notchGeometry = activeNotch
                    metrics.presentation = .compact
                    resolvedSize = Self.compactSize(notchGeometry: activeNotch)
                    contentSize = resolvedSize
                    metrics.viewportSize = resolvedSize
                }
            }
            defaultFrame = Self.frame(size: resolvedSize, on: screen, notchGeometry: notchGeometry)
        } else {
            defaultFrame = CGRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height, width: size.width, height: size.height)
        }
        let bounds = screenFrame ?? screenFrameOverride ?? (notchGeometry == nil ? screen?.visibleFrame : screen?.frame) ?? frame
        return position.frame(for: defaultFrame, within: bounds)
    }

    private static func compactSize(notchGeometry: NotchGeometry?) -> CGSize {
        CGSize(width: notchGeometry?.cutoutFrame.width ?? 360,
               height: notchGeometry.map { $0.cutoutFrame.height + 28 } ?? 64)
    }

    private static func notchGeometry(for screen: NSScreen?) -> NotchGeometry? {
        guard let screen else { return nil }
        return NotchGeometry.detect(screenFrame: screen.frame, safeAreaTop: screen.safeAreaInsets.top,
                                    leftArea: screen.auxiliaryTopLeftArea, rightArea: screen.auxiliaryTopRightArea)
    }

    private static func frame(size: CGSize, on screen: NSScreen?, notchGeometry: NotchGeometry? = nil) -> NSRect {
        guard let screen else { return NSRect(x: 0, y: 0, width: 0, height: 0) }
        if let notchGeometry {
            return NSRect(x: notchGeometry.cutoutFrame.midX - size.width / 2,
                          y: screen.frame.maxY - size.height, width: size.width, height: size.height)
        }
        return FocusPanelPlacement.frame(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaTop: screen.safeAreaInsets.top,
            size: size
        )
    }

    private static func frame(size: CGSize, in screenFrame: CGRect) -> NSRect {
        FocusPanelPlacement.frame(screenFrame: screenFrame, visibleFrame: screenFrame, safeAreaTop: 0, size: size)
    }
}

@MainActor
private final class FocusPanelMetrics: ObservableObject {
    @Published var viewportSize: CGSize
    @Published var expandedContentSize = CGSize(width: 360, height: 420)
    @Published var presentation = PanelPresentation.compact
    var isExpanded: Bool { presentation != .compact }
    var notchGeometry: NotchGeometry?

    init(viewportSize: CGSize, notchGeometry: NotchGeometry? = nil) {
        self.viewportSize = viewportSize
        self.notchGeometry = notchGeometry
    }
}

@MainActor
// shortcut: uses the foreground app's topmost normal window; switch to Accessibility-based focus if this approximation proves insufficient.
func activeApplicationScreen() -> NSScreen? {
    let screens = NSScreen.screens
    guard !screens.isEmpty else { return nil }
    lastActiveApplicationScreen = resolvedCachedScreen(lastActiveApplicationScreen, in: screens)
    let fallback = NSScreen.main ?? screens.first
    guard let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
          frontmostPID != ProcessInfo.processInfo.processIdentifier else { return lastActiveApplicationScreen ?? fallback }
    guard
          let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
          let window = windows.first(where: {
              ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == frontmostPID
                  && ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 0
          }),
          let bounds = window[kCGWindowBounds as String] as? NSDictionary else { return lastActiveApplicationScreen ?? fallback }

    var quartzFrame = CGRect()
    guard CGRectMakeWithDictionaryRepresentation(bounds as CFDictionary, &quartzFrame),
          let primaryScreen = screens.first(where: {
              ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == CGMainDisplayID()
          }) ?? screens.first else { return lastActiveApplicationScreen ?? fallback }
    let appKitFrame = CGRect(
        x: quartzFrame.minX,
        y: primaryScreen.frame.maxY - quartzFrame.maxY,
        width: quartzFrame.width,
        height: quartzFrame.height
    )
    var selectedScreen: NSScreen?
    var greatestIntersection: CGFloat = 0
    for screen in screens {
        let intersection = screen.frame.intersection(appKitFrame)
        let area = intersection.width * intersection.height
        if area > greatestIntersection {
            selectedScreen = screen
            greatestIntersection = area
        }
    }
    if let selectedScreen { lastActiveApplicationScreen = selectedScreen }
    return selectedScreen ?? lastActiveApplicationScreen ?? fallback
}

@MainActor private var lastActiveApplicationScreen: NSScreen?

/// Returns the current NSScreen for the cached screen's display ID, or nil if that display is gone.
func resolvedCachedScreen(_ cached: NSScreen?, in screens: [NSScreen]) -> NSScreen? {
    guard let id = cached?.displayID else { return nil }
    return screens.first { $0.displayID == id }
}

private extension NSScreen {
    var displayID: UInt32? { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value }
}

private struct FocusPanelRoot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var compactWidth: CGFloat = 176
    @ObservedObject var controller: FocusController
    @ObservedObject var metrics: FocusPanelMetrics
    let onDrag: (CGSize) -> Void
    let onExpanded: (Bool) -> Void
    let onControls: () -> Void
    let onNotchModeChanged: () -> Void
    let onContentSize: (CGSize) -> Void
    let onExpandedContentSize: (CGSize) -> Void
    let onTimerContentSize: (CGSize) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            if metrics.presentation == .timer, let notch = metrics.notchGeometry {
                VStack(spacing: 0) {
                    Color.clear.frame(width: notch.cutoutFrame.width, height: notch.cutoutFrame.height)
                    VStack(spacing: 6) {
                        HStack {
                            PanelDragHandle(onDrag: onDrag, language: controller.settings.language, value: "\(notchStatus(controller.session, now: controller.now, language: controller.settings.language)) · \(timerText(controller.session, now: controller.now))")
                                .frame(width: 24, height: 30)
                                .overlay(Circle().fill(controller.session.state == .running ? .green : .white.opacity(0.65)).frame(width: 7, height: 7).allowsHitTesting(false))
                            Spacer()
                            PanelExpandButton(title: "⌃", accessibilityLabel: controller.settings.language.t("Collapse", "Einklappen"), width: 36, height: 30, action: { onExpanded(false) })
                        }
                        Text(timerText(controller.session, now: controller.now))
                            .font(.system(size: 42, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .accessibilityLabel(controller.settings.language.t("Remaining time", "Verbleibende Zeit"))
                            .accessibilityValue(timerText(controller.session, now: controller.now))
                        Text(notchStatus(controller.session, now: controller.now, language: controller.settings.language))
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.7))
                            .accessibilityLabel(controller.settings.language.t("Session status", "Sitzungsstatus"))
                        PanelExpandButton(title: controller.settings.language.t("Controls", "Bedienung"), accessibilityLabel: controller.settings.language.t("Controls", "Bedienung"), action: onControls)
                            .frame(width: 90, height: 30)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .frame(width: metrics.viewportSize.width)
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: CompactPanelSizeKey.self, value: CGSize(width: metrics.viewportSize.width, height: notch.cutoutFrame.height + proxy.size.height))
                    })
                    .onPreferenceChange(CompactPanelSizeKey.self, perform: onTimerContentSize)
                }
                .transaction { $0.animation = nil }
                .transition(.opacity)
            } else if metrics.isExpanded {
                VStack(spacing: 0) {
                    if let notch = metrics.notchGeometry {
                        Color.clear.frame(width: notch.cutoutFrame.width, height: notch.cutoutFrame.height)
                    }
                    ScrollView(.vertical) {
                        FocusExpandedCard(controller: controller, onCollapse: {
                            onExpanded(false)
                        }, onSize: onExpandedContentSize)
                        .frame(width: max(0, metrics.viewportSize.width - 20))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10)
                        .padding(.top, metrics.notchGeometry == nil ? 10 : 0)
                        .padding(.bottom, 10)
                    }
                    .frame(width: metrics.viewportSize.width, height: FocusPanelViewport.height(
                        contentHeight: metrics.expandedContentSize.height - (metrics.notchGeometry?.cutoutFrame.height ?? 0),
                        availableHeight: metrics.viewportSize.height - (metrics.notchGeometry?.cutoutFrame.height ?? 0)
                    ))
                }
                .transaction { $0.animation = nil }
                .transition(.opacity)
            } else if let notch = metrics.notchGeometry {
                VStack(spacing: 0) {
                    Color.clear.frame(width: notch.cutoutFrame.width, height: notch.cutoutFrame.height)
                    HStack(spacing: 2) {
                        PanelDragHandle(onDrag: onDrag, language: controller.settings.language, value: "\(notchStatus(controller.session, now: controller.now, language: controller.settings.language)) · \(timerText(controller.session, now: controller.now))")
                            .frame(width: 24, height: 28)
                            .overlay(Circle().fill(controller.session.state == .running ? .green : .white.opacity(0.65)).frame(width: 7, height: 7).allowsHitTesting(false))
                        PanelExpandButton(title: "", accessibilityLabel: controller.settings.language.t("Open timer view", "Timeranzeige öffnen"), height: 28,
                                          accessibilityValue: "\(notchStatus(controller.session, now: controller.now, language: controller.settings.language)) · \(timerText(controller.session, now: controller.now))",
                                          action: { onExpanded(true) })
                            .frame(maxWidth: .infinity)
                            .overlay {
                                HStack(spacing: 3) {
                                    Text(notchStatus(controller.session, now: controller.now, language: controller.settings.language))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.6)
                                    Text("·")
                                    Text(timerText(controller.session, now: controller.now))
                                        .monospacedDigit()
                                        .fixedSize()
                                }
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                            }
                    }
                    .padding(.horizontal, 6)
                    .frame(width: notch.cutoutFrame.width, height: 28)
                    .foregroundStyle(.white)
                }
                .frame(width: metrics.viewportSize.width, height: metrics.viewportSize.height, alignment: .top)
                .frame(maxWidth: .infinity)
                .transaction { $0.animation = nil }
                .transition(.opacity)
            } else {
                HStack(spacing: 0) {
                    PanelDragHandle(onDrag: onDrag, language: controller.settings.language, value: "\(sessionDescription(controller.session, language: controller.settings.language)) · \(timerText(controller.session, now: controller.now))")
                        .frame(width: 24, height: 48)
                        .overlay(Circle().fill(controller.session.state == .running ? .green : .white.opacity(0.65)).frame(width: 7, height: 7).allowsHitTesting(false))
                    CompactIsland(controller: controller)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .overlay {
                            PanelExpandButton(title: "", accessibilityLabel: "Open Focus Island", height: 48,
                                              accessibilityValue: "\(sessionDescription(controller.session, language: controller.settings.language)) · \(timerText(controller.session, now: controller.now))",
                                              accessibilityHelp: controller.settings.language.t("Opens focus controls", "Öffnet die Fokussteuerung"),
                                              action: { onExpanded(true) })
                        }
                }
                .fixedSize(horizontal: true, vertical: false)
                .background(GeometryReader { proxy in
                    Color.clear
                        .onAppear { compactWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, width in compactWidth = width }
                })
                .frame(width: metrics.viewportSize.width, height: 64)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: CompactPanelSizeKey.self, value: proxy.size)
                })
                .onPreferenceChange(CompactPanelSizeKey.self, perform: onContentSize)
                .transaction { $0.animation = nil }
                .transition(.opacity)
            }
        }
        .frame(width: metrics.viewportSize.width, height: metrics.viewportSize.height, alignment: .top)
        .mask(alignment: .top) { panelSurface(mask: true) }
        .background(alignment: .top) { panelSurface() }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.clear)
        .onChange(of: controller.settings.notchModeEnabled) { _, _ in onNotchModeChanged() }
    }

    private func panelSurface(mask: Bool = false) -> some View {
        let notch = metrics.notchGeometry
        let compact = metrics.presentation == .compact
        let controls = metrics.presentation == .controls
        let top = notch?.cutoutFrame.height ?? (compact ? 8 : 10)
        let bottom: CGFloat = controls ? 10 : (notch == nil ? 8 : 0)
        let width = compact ? (notch?.cutoutFrame.width ?? compactWidth)
            : max(0, metrics.viewportSize.width - (controls ? 20 : 0))
        let height = compact ? (notch == nil ? 48 : 28) : max(0, metrics.viewportSize.height - top - bottom)
        let radius: CGFloat = compact ? (notch == nil ? 24 : 10) : (controls ? 22 : 20)
        let shape = UnevenRoundedRectangle(topLeadingRadius: compact && notch != nil ? 0 : radius,
                                          bottomLeadingRadius: radius, bottomTrailingRadius: radius,
                                          topTrailingRadius: compact && notch != nil ? 0 : radius)
        return VStack(spacing: 0) {
            if let notch {
                Rectangle().fill(.black).frame(width: notch.cutoutFrame.width, height: top)
            } else {
                Color.clear.frame(height: top)
            }
            shape.fill(mask ? .white : (controls ? Color(nsColor: .windowBackgroundColor).opacity(0.96) : .black))
                .overlay(shape.stroke(.white.opacity(controls && !mask ? 0.12 : 0), lineWidth: 1))
                .frame(width: width, height: height)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: FocusPanel.animationDuration), value: compactWidth)
        .allowsHitTesting(false)
        .preferredColorScheme(.dark)
    }
}

private struct CompactPanelSizeKey: PreferenceKey {
    static let defaultValue = CGSize(width: 360, height: 64)
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

private struct CompactIsland: View {
    @ObservedObject var controller: FocusController

    var body: some View {
        HStack(spacing: 10) {
            Text(controller.session.state == .running || controller.session.state == .paused
                 ? timerText(controller.session, now: controller.now) : "Open Focus Island")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .frame(height: 48)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Open Focus Island")
        .accessibilityValue("\(sessionDescription(controller.session, language: controller.settings.language)) · \(timerText(controller.session, now: controller.now))")
        .accessibilityHint(controller.settings.language.t("Opens focus controls", "Öffnet die Fokussteuerung"))
    }
}

@MainActor
private struct PanelExpandButton: NSViewRepresentable {
    var title = "⌄"
    var accessibilityLabel: String
    var width: CGFloat = 36
    var height: CGFloat = 48
    var alignment: NSTextAlignment = .center
    var accessibilityValue: String?
    var accessibilityHelp: String?
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.expand))
        button.frame = CGRect(x: 0, y: 0, width: width, height: height)
        button.isBordered = false
        button.alignment = alignment
        button.setAccessibilityElement(true)
        button.setAccessibilityRole(.button)
        button.setAccessibilityLabel(accessibilityLabel)
        button.setAccessibilityHelp(accessibilityHelp ?? accessibilityLabel)
        button.setAccessibilityValue(accessibilityValue)
        button.toolTip = accessibilityLabel
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        button.title = title
        button.alignment = alignment
        button.setAccessibilityLabel(accessibilityLabel)
        button.setAccessibilityHelp(accessibilityHelp ?? accessibilityLabel)
        button.setAccessibilityValue(accessibilityValue)
        button.toolTip = accessibilityLabel
        context.coordinator.action = action
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? width, height: proposal.height ?? height)
    }

    @MainActor
    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func expand() { action() }
    }
}

private struct PanelDragHandle: NSViewRepresentable {
    let onDrag: (CGSize) -> Void
    let language: AppLanguage
    let value: String

    func makeNSView(context: Context) -> PanelDragHandleView {
        let view = PanelDragHandleView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: PanelDragHandleView, context: Context) {
        view.onDrag = onDrag
        view.setAccessibilityLabel(language.t("Move panel", "Panel verschieben"))
        view.setAccessibilityHelp(language.t("Move with arrow keys", "Mit Pfeiltasten verschieben"))
        view.setAccessibilityValue(value)
    }
}

private final class PanelDragHandleView: NSView {
    var onDrag: ((CGSize) -> Void)?
    private var lastPoint: NSPoint?

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 24, height: 24) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = NSUserInterfaceItemIdentifier("panel-drag-handle")
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        lastPoint = window?.convertPoint(toScreen: event.locationInWindow)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let lastPoint, let point = window?.convertPoint(toScreen: event.locationInWindow) else { return }
        onDrag?(CGSize(width: point.x - lastPoint.x, height: point.y - lastPoint.y))
        self.lastPoint = point
    }

    override func mouseUp(with event: NSEvent) { lastPoint = nil }

    override func keyDown(with event: NSEvent) {
        let distance: CGFloat = 10
        switch event.keyCode {
        case 123: onDrag?(CGSize(width: -distance, height: 0))
        case 124: onDrag?(CGSize(width: distance, height: 0))
        case 125: onDrag?(CGSize(width: 0, height: -distance))
        case 126: onDrag?(CGSize(width: 0, height: distance))
        default: super.keyDown(with: event)
        }
    }
}

private struct FocusExpandedCard: View {
    @ObservedObject var controller: FocusController
    let onCollapse: () -> Void
    let onSize: (CGSize) -> Void
    @State private var taskName = ""

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Open Focus Island").font(.system(size: 13, weight: .semibold))
                Spacer()
                PanelExpandButton(title: "⌃", accessibilityLabel: controller.settings.language.t("Collapse", "Einklappen"), action: onCollapse)
                    .frame(width: 36, height: 48)
            }
            if let kind = controller.awaitingAcknowledgement { CompletionAcknowledgementCard(controller: controller, kind: kind) }
            Text(timerText(controller.session, now: controller.now))
                .font(.system(size: 42, weight: .medium, design: .rounded))
                .monospacedDigit()
                .accessibilityLabel(controller.settings.language.t("Remaining time", "Verbleibende Zeit"))
                .accessibilityValue(timerText(controller.session, now: controller.now))
            Text(sessionDescription(controller.session, language: controller.settings.language))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
                .accessibilityLabel(controller.settings.language.t("Session status", "Sitzungsstatus"))
                .accessibilityValue(sessionDescription(controller.session, language: controller.settings.language))

            if controller.awaitingAcknowledgement != nil {
            } else if controller.session.state == .idle || controller.session.state == .completed {
                TextField(controller.settings.language.t("What are you working on? (optional)", "Woran arbeitest du? (optional)"), text: $taskName)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(controller.settings.language.t("Task", "Aufgabe"))
                SessionStartButtons(controller: controller, taskName: $taskName)
            } else {
                SessionActionButtons(controller: controller)
            }

            ControllerError(controller: controller)
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity)
        .buttonStyle(.bordered)
        .controlSize(.large)
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { onSize(CGSize(width: proxy.size.width + 20, height: proxy.size.height + 20)) }
                .onChange(of: proxy.size) { _, size in onSize(CGSize(width: size.width + 20, height: size.height + 20)) }
        })
        .preferredColorScheme(.dark)
    }
}

private struct CompletionAcknowledgementCard: View {
    @ObservedObject var controller: FocusController
    let kind: FocusSession.Kind

    var body: some View {
        let language = controller.settings.language
        let gotIt = language.t("Got it", "Verstanden")
        let next: FocusSession.Kind = kind == .focus ? controller.session.recommendedBreak : .focus
        VStack(spacing: 8) {
            Text(kind == .focus ? language.t("Focus complete", "Fokus abgeschlossen") : language.t("Break complete", "Pause abgeschlossen"))
                .font(.system(size: 17, weight: .semibold))
            HStack(spacing: 8) {
                Button(gotIt) { controller.acknowledgeCompletion() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityLabel(gotIt)
                Button(kind == .focus ? language.t("Start break", "Pause starten") : language.t("Start focus", "Fokus starten")) { controller.start(kind: next) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct SessionStartButtons: View {
    @ObservedObject var controller: FocusController
    @Binding var taskName: String

    var body: some View {
        VStack(spacing: 8) {
            Button(controller.settings.language.t("Start focus", "Fokus starten")) { controller.start(kind: .focus, taskName: taskName) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            if controller.session.recommendedBreak == .longBreak {
                VStack(spacing: 8) { breakButtons }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { breakButtons }
                    VStack(spacing: 8) { breakButtons }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var breakButtons: some View {
        Button { controller.start(kind: .shortBreak) } label: {
            Text(controller.settings.language.t("Short break", "Kurze Pause")).fixedSize().frame(maxWidth: .infinity)
        }
        Button { controller.start(kind: .longBreak) } label: {
            Text(controller.session.recommendedBreak == .longBreak ? controller.settings.language.t("Long break recommended", "Lange Pause empfohlen") : controller.settings.language.t("Long break", "Lange Pause"))
                .fixedSize().frame(maxWidth: .infinity)
        }
    }
}

private struct SessionActionButtons: View {
    @ObservedObject var controller: FocusController

    var body: some View {
        VStack(spacing: 8) {
            if controller.session.state == .paused {
                Button(controller.settings.language.t("Resume", "Fortsetzen"), action: controller.resume)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(controller.settings.language.t("Pause", "Pausieren"), action: controller.pause)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { secondaryButtons }
                VStack(spacing: 8) { secondaryButtons }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var secondaryButtons: some View {
        Button(action: controller.finish) {
            Text(controller.settings.language.t("Finish", "Beenden")).fixedSize().frame(maxWidth: .infinity)
        }
        if controller.session.kind == .focus {
            Button(action: controller.skip) {
                Text(controller.settings.language.t("Switch to break", "Zur Pause wechseln")).fixedSize().frame(maxWidth: .infinity)
            }
        }
    }
}

struct MenuBarControls: View {
    @ObservedObject var controller: FocusController
    let onShowHistory: () -> Void
    @State private var taskName = ""
    @State private var settingsExpanded = false

    var body: some View {
        let settingsAction = settingsExpanded
            ? controller.settings.language.t("Hide settings", "Einstellungen ausblenden")
            : controller.settings.language.t("Show settings", "Einstellungen anzeigen")
        return VStack(alignment: .leading, spacing: 12) {
            Text("Open Focus Island").font(.headline)
            if controller.session.state == .running || controller.session.state == .paused {
                Text("\(sessionDescription(controller.session, language: controller.settings.language)) · \(timerText(controller.session, now: controller.now))")
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
                SessionActionButtons(controller: controller)
            } else {
                TextField(controller.settings.language.t("Task (optional)", "Aufgabe (optional)"), text: $taskName)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(controller.settings.language.t("Task", "Aufgabe"))
                SessionStartButtons(controller: controller, taskName: $taskName)
            }
            PanelExpandButton(title: settingsAction,
                              accessibilityLabel: settingsAction, height: 36, alignment: .left,
                              accessibilityValue: settingsExpanded ? controller.settings.language.t("Expanded", "Geöffnet") : controller.settings.language.t("Collapsed", "Geschlossen"),
                              action: { settingsExpanded.toggle() })
                .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36)
            if settingsExpanded {
                FocusSettingsForm(controller: controller)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ControllerError(controller: controller)
            Divider()
            HStack {
                Button(controller.settings.language.t("Quit", "Beenden")) { NSApp.terminate(nil) }
                Spacer()
                PanelExpandButton(title: "", accessibilityLabel: controller.settings.language.t("Show history", "Verlauf anzeigen"), height: 36, action: onShowHistory)
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 16))
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
            }
        }
        .padding(12)
        .frame(width: 340)
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
}

private struct FocusSettingsForm: View {
    @ObservedObject var controller: FocusController
    @State private var focusMinutes: Double
    @State private var shortBreakMinutes: Double
    @State private var longBreakMinutes: Double

    init(controller: FocusController) {
        self.controller = controller
        _focusMinutes = State(initialValue: controller.settings.focusDuration / 60)
        _shortBreakMinutes = State(initialValue: controller.settings.shortBreakDuration / 60)
        _longBreakMinutes = State(initialValue: controller.settings.longBreakDuration / 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            minuteField(controller.settings.language.t("Focus", "Fokus"), value: $focusMinutes)
            minuteField(controller.settings.language.t("Short break", "Kurze Pause"), value: $shortBreakMinutes)
            minuteField(controller.settings.language.t("Long break", "Lange Pause"), value: $longBreakMinutes)
            Toggle(isOn: Binding(
                get: { controller.settings.notchModeEnabled },
                set: { controller.setNotchModeEnabled($0) }
            )) {
                Text(controller.settings.language.t("Notch mode", "Notch-Modus")).frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .font(.system(size: 12))
            Toggle(controller.settings.language.t("Timer in menu bar", "Timer in der Menüleiste"), isOn: Binding(
                get: { controller.settings.menuBarTimerEnabled },
                set: { controller.setMenuBarTimerEnabled($0) }
            ))
            .font(.system(size: 12))
            Toggle(controller.settings.language.t("Notifications", "Benachrichtigungen"), isOn: Binding(
                get: { controller.settings.notificationsEnabled },
                set: { controller.setNotificationsEnabled($0) }
            ))
            .font(.system(size: 12))
            Toggle(controller.settings.language.t("Completion sounds", "Abschlusstöne"), isOn: Binding(
                get: { controller.settings.soundsEnabled },
                set: { controller.setSoundsEnabled($0) }
            ))
            .font(.system(size: 12))
            .accessibilityLabel(controller.settings.language.t("Completion sounds", "Abschlusstöne"))
            Picker(controller.settings.language.t("Language", "Sprache"), selection: Binding(
                get: { controller.settings.language },
                set: { controller.setLanguage($0) }
            )) {
                Text("English").tag(AppLanguage.english)
                Text("Deutsch").tag(AppLanguage.german)
            }
            .pickerStyle(.segmented)
            .font(.system(size: 12))
            Button(controller.settings.language.t("Save", "Speichern")) {
                _ = controller.saveSettings(FocusSettings(
                    focusDuration: focusMinutes * 60,
                    shortBreakDuration: shortBreakMinutes * 60,
                    longBreakDuration: longBreakMinutes * 60,
                    notificationsEnabled: controller.settings.notificationsEnabled
                ))
            }
        }
        .onChange(of: controller.settings) { _, settings in
            focusMinutes = settings.focusDuration / 60
            shortBreakMinutes = settings.shortBreakDuration / 60
            longBreakMinutes = settings.longBreakDuration / 60
        }
    }

    private func minuteField(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 64)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel(controller.settings.language.t("\(title) in minutes", "\(title) in Minuten"))
        }
        .font(.system(size: 12))
    }
}

struct ControllerError: View {
    @ObservedObject var controller: FocusController

    var body: some View {
        if let error = controller.error {
            Text(error)
                .font(.system(size: 11))
                .foregroundStyle(.red)
                .accessibilityLabel(controller.settings.language.t("Error: \(error)", "Fehler: \(error)"))
        }
    }
}

func historyDetail(_ entry: FocusHistoryEntry, language: AppLanguage) -> String {
    let date = entry.completedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: language.rawValue)))
    let minutes = Int((entry.plannedDuration / 60).rounded())
    return language.t("\(date) · \(minutes) min", "\(date) · \(minutes) Min.")
}

private func timerText(_ session: FocusSession, now: Date) -> String {
    let seconds = max(0, Int(session.remaining(now: now).rounded(.up)))
    return String(format: "%02d:%02d", seconds / 60, seconds % 60)
}

/// Short notch status without task name: running → almost done (remaining <= 60 s) → complete; paused stays paused.
func notchStatus(_ session: FocusSession, now: Date, language: AppLanguage) -> String {
    let kind = kindName(session.kind, language: language)
    switch session.state {
    case .running: return session.remaining(now: now) <= 60 ? language.t("\(kind) almost done", "\(kind) bald fertig") : language.t("\(kind) running", "\(kind) läuft")
    case .paused: return language.t("\(kind) paused", "\(kind) pausiert")
    case .idle, .completed: return sessionDescription(session, language: language)
    }
}

func kindName(_ kind: FocusSession.Kind, language: AppLanguage) -> String {
    switch kind {
    case .focus: language.t("Focus", "Fokus")
    case .shortBreak: language.t("Short break", "Kurze Pause")
    case .longBreak: language.t("Long break", "Lange Pause")
    }
}

func sessionDescription(_ session: FocusSession, language: AppLanguage) -> String {
    let kind = kindName(session.kind, language: language)
    switch session.state {
    case .idle: return language.t("Ready for a session", "Bereit für eine Sitzung")
    case .running: return session.taskName.map { "\(kind) · \($0)" } ?? language.t("\(kind) running", "\(kind) läuft")
    case .paused: return session.taskName.map { language.t("\(kind) paused · \($0)", "\(kind) pausiert · \($0)") } ?? language.t("\(kind) paused", "\(kind) pausiert")
    case .completed: return language.t("\(kind) complete", "\(kind) abgeschlossen")
    }
}
