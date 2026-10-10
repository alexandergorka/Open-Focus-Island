import AppKit
import Vision
import SwiftUI
@testable import OpenFocusIsland
import XCTest

@MainActor
func descendantViews(of view: NSView?) -> [NSView] {
    guard let view else { return [] }
    return [view] + view.subviews.flatMap(descendantViews)
}

@MainActor
func recognizedText(in view: NSView) throws -> [(text: String, frame: CGRect)] {
    let bounds = view.bounds
    let rep = try XCTUnwrap(NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(bounds.width * 2),
        pixelsHigh: Int(bounds.height * 2),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ))
    rep.size = bounds.size
    view.cacheDisplay(in: bounds, to: rep)
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    try VNImageRequestHandler(cgImage: try XCTUnwrap(rep.cgImage)).perform([request])
    return (request.results ?? []).compactMap { observation in
        guard let candidate = observation.topCandidates(1).first else { return nil }
        return (candidate.string, observation.boundingBox)
    }
}

@MainActor
func makeSettingsMenu(_ controller: FocusController) -> NSPanel {
    let window = NSPanel(contentRect: CGRect(x: 100, y: 100, width: 340, height: 700),
                         styleMask: [.borderless], backing: .buffered, defer: false)
    let delegate = AppDelegate(controller: controller)
    window.contentView = NSHostingView(rootView: MenuBarControls(controller: controller,
        onShowHistory: { delegate.showHistory() }).fixedSize()
        .background(Color(nsColor: .windowBackgroundColor)).preferredColorScheme(.dark))
    settleSettingsMenu(window)
    window.makeKeyAndOrderFront(nil)
    return window
}

@MainActor
func settleSettingsMenu(_ window: NSWindow) {
    for _ in 0..<4 {
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        if let content = window.contentView {
            let top = window.frame.maxY
            window.setContentSize(content.fittingSize)
            window.setFrameOrigin(NSPoint(x: window.frame.minX, y: top - window.frame.height))
            content.layoutSubtreeIfNeeded()
        }
    }
}

@MainActor
func settingsMenuButton(_ label: String, in window: NSWindow) throws -> NSButton {
    try XCTUnwrap(descendantViews(of: window.contentView).compactMap { $0 as? NSButton }
        .first { $0.accessibilityLabel() == label }, "Visible menu button missing: \(label)")
}
