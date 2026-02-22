import AppKit
import Carbon.HIToolbox
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hotKeyManager = GlobalHotKeyManager()
    private var hotKeyObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        hotKeyManager.register(configuration: HotKeySettingsStore.shared.configuration)

        hotKeyObserver = HotKeySettingsStore.shared.$configuration
            .removeDuplicates()
            .sink { [weak self] configuration in
                self?.hotKeyManager.register(configuration: configuration)
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

        sender.windows.first?.makeKeyAndOrderFront(nil)
        return true
    }
}

@MainActor
final class GlobalHotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    private let signature: OSType = 0x4D434C48 // 'MCLH'
    private let hotKeyID: UInt32 = 1

    private static let hotKeyHandler: EventHandlerUPP = { _, event, userData in
        guard let userData else {
            return noErr
        }

        let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
        return manager.handleHotKey(event)
    }

    func register(configuration: HotKeyConfiguration) {
        unregister()

        let normalized = configuration.normalized
        guard let keyCode = Self.keyCode(for: normalized.key) else {
            return
        }

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

        let carbonHotKeyID = EventHotKeyID(signature: signature, id: hotKeyID)
        let modifiers = Self.carbonModifiers(for: normalized)
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            carbonHotKeyID,
            dispatcherTarget,
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr else {
            unregister()
            return
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
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

        guard pressedHotKeyID.signature == signature, pressedHotKeyID.id == hotKeyID else {
            return noErr
        }

        NSApp.activate(ignoringOtherApps: true)

        if let window = NSApp.windows.first {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }

            window.makeKeyAndOrderFront(nil)
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
