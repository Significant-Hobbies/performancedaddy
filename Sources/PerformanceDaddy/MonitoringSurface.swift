import AppKit
import SwiftUI

/// Tracks each diagnostic surface independently, including menu popovers.
/// Application activation alone cannot tell whether another window is visible.
struct MonitoringSurface: NSViewRepresentable {
    let model: LiveViewModel

    func makeNSView(context: Context) -> SurfaceView { SurfaceView(model: model) }
    func updateNSView(_ nsView: SurfaceView, context: Context) {}
    static func dismantleNSView(_ nsView: SurfaceView, coordinator: ()) { nsView.detach() }

    final class SurfaceView: NSView {
        private let id = UUID()
        private weak var model: LiveViewModel?
        private var observers: [NSObjectProtocol] = []

        init(model: LiveViewModel) {
            self.model = model
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            detach()
            guard let window else { return }
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                         NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] event in
                    let closing = event.name == NSWindow.willCloseNotification
                    MainActor.assumeIsolated {
                        if closing { self?.detach() }
                        else { self?.reportVisibility() }
                    }
                })
            }
            reportVisibility()
        }

        private func reportVisibility() {
            let visible = window.map { $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible) } ?? false
            model?.setSurfaceVisible(id, visible: visible)
        }

        func detach() {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers.removeAll()
            model?.setSurfaceVisible(id, visible: false)
        }
    }
}
