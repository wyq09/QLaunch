import AppKit
import SwiftUI

struct VisualEffectBackdrop: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        view.material = material
        view.blendingMode = blendingMode
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
}

struct WindowConfigurator: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else {
                return
            }

            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
            window.hasShadow = true

            let windowID = ObjectIdentifier(window)
            if !context.coordinator.didConfigureWindowIDs.contains(windowID) {
                if let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
                    window.setFrame(visibleFrame, display: true)
                }

                context.coordinator.didConfigureWindowIDs.insert(windowID)
            }
        }
    }

    final class Coordinator {
        var didConfigureWindowIDs = Set<ObjectIdentifier>()
    }
}

struct SwipeGestureRegistrar: NSViewRepresentable {
    let onSwipeLeft: () -> Void
    let onSwipeRight: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSwipeLeft: onSwipeLeft, onSwipeRight: onSwipeRight)
    }

    func makeNSView(context: Context) -> NSView {
        let anchor = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.installIfNeeded()
        }
        return anchor
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onSwipeLeft = onSwipeLeft
        context.coordinator.onSwipeRight = onSwipeRight

        DispatchQueue.main.async {
            context.coordinator.installIfNeeded()
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var onSwipeLeft: () -> Void
        var onSwipeRight: () -> Void

        private var localScrollMonitor: Any?
        private var accumulatedDeltaX: CGFloat = 0
        private var accumulatedDeltaY: CGFloat = 0

        init(onSwipeLeft: @escaping () -> Void, onSwipeRight: @escaping () -> Void) {
            self.onSwipeLeft = onSwipeLeft
            self.onSwipeRight = onSwipeRight
        }

        func installIfNeeded() {
            guard localScrollMonitor == nil else {
                return
            }

            localScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else {
                    return event
                }

                self.handle(event)
                return event
            }
        }

        private func handle(_ event: NSEvent) {
            guard event.phase != [] || event.momentumPhase != [] else {
                return
            }

            if event.phase == .began {
                accumulatedDeltaX = 0
                accumulatedDeltaY = 0
            }

            accumulatedDeltaX += event.scrollingDeltaX
            accumulatedDeltaY += event.scrollingDeltaY

            let gestureEnded = event.phase == .ended || event.momentumPhase == .ended || event.phase == .cancelled
            guard gestureEnded else {
                return
            }

            defer {
                accumulatedDeltaX = 0
                accumulatedDeltaY = 0
            }

            let horizontalDistance = abs(accumulatedDeltaX)
            let verticalDistance = abs(accumulatedDeltaY)

            guard horizontalDistance >= 50, horizontalDistance > verticalDistance else {
                return
            }

            if accumulatedDeltaX < 0 {
                onSwipeLeft()
            } else {
                onSwipeRight()
            }
        }
    }
}
