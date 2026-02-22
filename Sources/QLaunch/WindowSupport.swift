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
    static let launchpadWindowIdentifier = "qlaunch.window.launchpad"

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
            window.isMovableByWindowBackground = false
            window.hasShadow = true
            if window.identifier == nil {
                window.identifier = NSUserInterfaceItemIdentifier(Self.launchpadWindowIdentifier)
            }

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
        private var lastSwipeUptime: TimeInterval = 0

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
            // Ignore momentum-only events to avoid double page turns on a single swipe.
            guard event.phase != [] else {
                return
            }

            if event.phase == .began {
                accumulatedDeltaX = 0
                accumulatedDeltaY = 0
            }

            accumulatedDeltaX += event.scrollingDeltaX
            accumulatedDeltaY += event.scrollingDeltaY

            let gestureEnded = event.phase == .ended || event.phase == .cancelled
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

            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastSwipeUptime >= 0.24 else {
                return
            }

            if accumulatedDeltaX < 0 {
                onSwipeLeft()
            } else {
                onSwipeRight()
            }

            lastSwipeUptime = now
        }
    }
}

struct ArrowKeyPagingRegistrar: NSViewRepresentable {
    let onLeftArrow: () -> Void
    let onRightArrow: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onLeftArrow: onLeftArrow, onRightArrow: onRightArrow)
    }

    func makeNSView(context: Context) -> NSView {
        let anchor = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.installIfNeeded()
        }
        return anchor
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onLeftArrow = onLeftArrow
        context.coordinator.onRightArrow = onRightArrow
        DispatchQueue.main.async {
            context.coordinator.installIfNeeded()
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var onLeftArrow: () -> Void
        var onRightArrow: () -> Void

        private var localKeyMonitor: Any?

        init(onLeftArrow: @escaping () -> Void, onRightArrow: @escaping () -> Void) {
            self.onLeftArrow = onLeftArrow
            self.onRightArrow = onRightArrow
        }

        func installIfNeeded() {
            guard localKeyMonitor == nil else {
                return
            }

            localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else {
                    return event
                }

                return self.handle(event)
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            if isEditingText {
                return event
            }

            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard modifiers.isEmpty else {
                return event
            }

            switch event.keyCode {
            case 123: // left arrow
                onLeftArrow()
                return nil
            case 124: // right arrow
                onRightArrow()
                return nil
            default:
                return event
            }
        }

        private var isEditingText: Bool {
            guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else {
                return false
            }

            return textView.isEditable
        }
    }
}

struct EscapeKeyRegistrar: NSViewRepresentable {
    let windowIdentifier: String
    let onEscape: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(windowIdentifier: windowIdentifier, onEscape: onEscape)
    }

    func makeNSView(context: Context) -> NSView {
        let anchor = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.installIfNeeded()
        }
        return anchor
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.windowIdentifier = windowIdentifier
        context.coordinator.onEscape = onEscape
        DispatchQueue.main.async {
            context.coordinator.installIfNeeded()
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var windowIdentifier: String
        var onEscape: () -> Void

        private var localKeyMonitor: Any?

        init(windowIdentifier: String, onEscape: @escaping () -> Void) {
            self.windowIdentifier = windowIdentifier
            self.onEscape = onEscape
        }

        func installIfNeeded() {
            guard localKeyMonitor == nil else {
                return
            }

            localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else {
                    return event
                }
                return self.handle(event)
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard event.keyCode == 53 else { // ESC
                return event
            }

            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard modifiers.isEmpty else {
                return event
            }

            guard NSApp.keyWindow?.identifier?.rawValue == windowIdentifier else {
                return event
            }

            onEscape()
            return nil
        }
    }
}

struct VerticalArrowKeyRegistrar: NSViewRepresentable {
    let windowIdentifier: String
    let onArrowUp: () -> Void
    let onArrowDown: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            windowIdentifier: windowIdentifier,
            onArrowUp: onArrowUp,
            onArrowDown: onArrowDown
        )
    }

    func makeNSView(context: Context) -> NSView {
        let anchor = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.installIfNeeded()
        }
        return anchor
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.windowIdentifier = windowIdentifier
        context.coordinator.onArrowUp = onArrowUp
        context.coordinator.onArrowDown = onArrowDown
        DispatchQueue.main.async {
            context.coordinator.installIfNeeded()
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var windowIdentifier: String
        var onArrowUp: () -> Void
        var onArrowDown: () -> Void

        private var localKeyMonitor: Any?

        init(windowIdentifier: String, onArrowUp: @escaping () -> Void, onArrowDown: @escaping () -> Void) {
            self.windowIdentifier = windowIdentifier
            self.onArrowUp = onArrowUp
            self.onArrowDown = onArrowDown
        }

        func installIfNeeded() {
            guard localKeyMonitor == nil else {
                return
            }

            localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else {
                    return event
                }
                return self.handle(event)
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard modifiers.isEmpty else {
                return event
            }

            guard NSApp.keyWindow?.identifier?.rawValue == windowIdentifier else {
                return event
            }

            switch event.keyCode {
            case 126: // up arrow
                onArrowUp()
                return nil
            case 125: // down arrow
                onArrowDown()
                return nil
            default:
                return event
            }
        }
    }
}
