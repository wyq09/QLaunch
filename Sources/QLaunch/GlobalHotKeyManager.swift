import AppKit
import Carbon.HIToolbox
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hotKeyManager = GlobalHotKeyManager()
    private var hotKeyObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerHotKeys(HotKeySettingsStore.shared.settings)

        hotKeyObserver = HotKeySettingsStore.shared.$settings
            .removeDuplicates()
            .sink { [weak self] settings in
                self?.registerHotKeys(settings)
            }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyObserver?.cancel()
        hotKeyManager.unregister()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else {
            return true
        }

        showLaunchpadWindow()
        return true
    }

    private func registerHotKeys(_ settings: HotKeySettings) {
        hotKeyManager.register(
            settings: settings,
            onLaunchpad: { [weak self] in
                self?.showLaunchpadWindow()
            },
            onSpotlight: {
                SpotlightSearchController.shared.toggle()
            }
        )
    }

    private func showLaunchpadWindow() {
        NSApp.activate(ignoringOtherApps: true)

        if let launchpadWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == WindowConfigurator.launchpadWindowIdentifier }) {
            if launchpadWindow.isMiniaturized {
                launchpadWindow.deminiaturize(nil)
            }
            launchpadWindow.makeKeyAndOrderFront(nil)
            return
        }

        if let firstWindow = NSApp.windows.first {
            if firstWindow.isMiniaturized {
                firstWindow.deminiaturize(nil)
            }
            firstWindow.makeKeyAndOrderFront(nil)
        }
    }
}

@MainActor
final class GlobalHotKeyManager {
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var eventHandlerRef: EventHandlerRef?

    private let signature: OSType = 0x514C484B // 'QLHK'

    private let launchpadHotKeyID: UInt32 = 1
    private let spotlightHotKeyID: UInt32 = 2

    private var onLaunchpad: () -> Void = {}
    private var onSpotlight: () -> Void = {}

    private static let hotKeyHandler: EventHandlerUPP = { _, event, userData in
        guard let userData else {
            return noErr
        }

        let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
        return manager.handleHotKey(event)
    }

    func register(settings: HotKeySettings, onLaunchpad: @escaping () -> Void, onSpotlight: @escaping () -> Void) {
        unregister()

        self.onLaunchpad = onLaunchpad
        self.onSpotlight = onSpotlight

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let dispatcherTarget = GetEventDispatcherTarget()
        let installStatus = InstallEventHandler(
            dispatcherTarget,
            Self.hotKeyHandler,
            1,
            &eventType,
            userData,
            &eventHandlerRef
        )

        guard installStatus == noErr else {
            return
        }

        let normalizedSettings = settings.normalized
        let launchpadRegistered = registerHotKey(configuration: normalizedSettings.launchpad, id: launchpadHotKeyID)
        let spotlightRegistered = registerHotKey(configuration: normalizedSettings.spotlight, id: spotlightHotKeyID)

        if !launchpadRegistered && !spotlightRegistered {
            unregister()
        }
    }

    func unregister() {
        for (_, hotKeyRef) in hotKeyRefs {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRefs.removeAll(keepingCapacity: true)

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private func registerHotKey(configuration: HotKeyConfiguration, id: UInt32) -> Bool {
        let normalized = configuration.normalized
        guard let keyCode = Self.keyCode(for: normalized.key) else {
            return false
        }

        let carbonHotKeyID = EventHotKeyID(signature: signature, id: id)
        let modifiers = Self.carbonModifiers(for: normalized)
        let dispatcherTarget = GetEventDispatcherTarget()

        var hotKeyRef: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            carbonHotKeyID,
            dispatcherTarget,
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr, let hotKeyRef else {
            return false
        }

        hotKeyRefs[id] = hotKeyRef
        return true
    }

    private func handleHotKey(_ event: EventRef?) -> OSStatus {
        var pressedHotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &pressedHotKeyID
        )

        guard status == noErr else {
            return status
        }

        guard pressedHotKeyID.signature == signature else {
            return noErr
        }

        switch pressedHotKeyID.id {
        case launchpadHotKeyID:
            onLaunchpad()
        case spotlightHotKeyID:
            onSpotlight()
        default:
            break
        }

        return noErr
    }

    private static func carbonModifiers(for configuration: HotKeyConfiguration) -> UInt32 {
        var modifiers: UInt32 = 0

        if configuration.command { modifiers |= UInt32(cmdKey) }
        if configuration.option { modifiers |= UInt32(optionKey) }
        if configuration.control { modifiers |= UInt32(controlKey) }
        if configuration.shift { modifiers |= UInt32(shiftKey) }

        return modifiers
    }

    private static func keyCode(for key: String) -> UInt32? {
        switch key.uppercased() {
        case "A": return UInt32(kVK_ANSI_A)
        case "B": return UInt32(kVK_ANSI_B)
        case "C": return UInt32(kVK_ANSI_C)
        case "D": return UInt32(kVK_ANSI_D)
        case "E": return UInt32(kVK_ANSI_E)
        case "F": return UInt32(kVK_ANSI_F)
        case "G": return UInt32(kVK_ANSI_G)
        case "H": return UInt32(kVK_ANSI_H)
        case "I": return UInt32(kVK_ANSI_I)
        case "J": return UInt32(kVK_ANSI_J)
        case "K": return UInt32(kVK_ANSI_K)
        case "L": return UInt32(kVK_ANSI_L)
        case "M": return UInt32(kVK_ANSI_M)
        case "N": return UInt32(kVK_ANSI_N)
        case "O": return UInt32(kVK_ANSI_O)
        case "P": return UInt32(kVK_ANSI_P)
        case "Q": return UInt32(kVK_ANSI_Q)
        case "R": return UInt32(kVK_ANSI_R)
        case "S": return UInt32(kVK_ANSI_S)
        case "T": return UInt32(kVK_ANSI_T)
        case "U": return UInt32(kVK_ANSI_U)
        case "V": return UInt32(kVK_ANSI_V)
        case "W": return UInt32(kVK_ANSI_W)
        case "X": return UInt32(kVK_ANSI_X)
        case "Y": return UInt32(kVK_ANSI_Y)
        case "Z": return UInt32(kVK_ANSI_Z)
        case "0": return UInt32(kVK_ANSI_0)
        case "1": return UInt32(kVK_ANSI_1)
        case "2": return UInt32(kVK_ANSI_2)
        case "3": return UInt32(kVK_ANSI_3)
        case "4": return UInt32(kVK_ANSI_4)
        case "5": return UInt32(kVK_ANSI_5)
        case "6": return UInt32(kVK_ANSI_6)
        case "7": return UInt32(kVK_ANSI_7)
        case "8": return UInt32(kVK_ANSI_8)
        case "9": return UInt32(kVK_ANSI_9)
        default:
            return nil
        }
    }
}
