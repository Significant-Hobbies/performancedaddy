import AppKit
import SwiftUI

/// Tracks each diagnostic surface independently, including menu popovers.
/// Application activation alone cannot tell whether another window is visible.
struct MonitoringSurface: NSViewRepresentable {
    let model: LiveViewModel
    var tracksSampling = true
    var onWindowOpen: ((Bool) -> Void)? = nil

    func makeNSView(context: Context) -> SurfaceView { SurfaceView(model: model, tracksSampling: tracksSampling, onWindowOpen: onWindowOpen) }
    func updateNSView(_ nsView: SurfaceView, context: Context) { nsView.onWindowOpen = onWindowOpen }
    static func dismantleNSView(_ nsView: SurfaceView, coordinator: ()) { nsView.detach() }

    final class SurfaceView: NSView {
        private let id = UUID()
        private weak var model: LiveViewModel?
        private var observers: [NSObjectProtocol] = []
        var onWindowOpen: ((Bool) -> Void)?
        private var lastOpen: Bool?
        private let tracksSampling: Bool

        init(model: LiveViewModel, tracksSampling: Bool = true, onWindowOpen: ((Bool) -> Void)? = nil) {
            self.model = model
            self.tracksSampling = tracksSampling
            self.onWindowOpen = onWindowOpen
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
                        if closing {
                            guard let self else { return }
                            self.reportOpen(false)
                            if self.tracksSampling { self.model?.setSurfaceVisible(self.id, visible: false) }
                        }
                        else { self?.reportVisibility() }
                    }
                })
            }
            reportVisibility()
        }

        private func reportVisibility() {
            let visible = window.map { $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible) } ?? false
            if tracksSampling { model?.setSurfaceVisible(id, visible: visible) }
            // Ordering out or hiding slows sampling without discarding view
            // state. Only willClose marks an already-open window closed.
            if lastOpen == nil || window?.isVisible == true { reportOpen(window?.isVisible == true) }
        }

        private func reportOpen(_ open: Bool) {
            guard lastOpen != open else { return }
            lastOpen = open
            // NSView callbacks can occur during a SwiftUI update. Defer the
            // state change until after that update rather than re-enter it.
            Task { @MainActor [weak self] in
                guard let self, self.lastOpen == open else { return }
                self.onWindowOpen?(open)
            }
        }

        func detach() {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers.removeAll()
            if tracksSampling { model?.setSurfaceVisible(id, visible: false) }
        }
    }
}

/// Closing a window releases its tables, inspectors and artwork instead of
/// retaining a subscribed diagnostic view tree for an always-on session.
/// Sampling and alert state remain owned by the app, outside this view.
struct DashboardWindowContent: View {
    let diagnosis: DiagnosisViewModel
    let live: LiveViewModel
    @State private var windowOpen = true
    @State private var destination = "Processes"

    var body: some View {
        ZStack {
            if windowOpen {
                DashboardView(model: diagnosis, live: live, initialDestination: destination,
                              onDestinationChanged: { destination = $0 })
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 980, minHeight: 800)
        .background(MonitoringSurface(model: live, onWindowOpen: { windowOpen = $0 }))
    }
}
