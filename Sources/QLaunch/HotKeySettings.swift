import Foundation

struct HotKeyConfiguration: Codable, Equatable {
    var key: String
    var command: Bool
    var option: Bool
    var control: Bool
    var shift: Bool

    static let legacyStorageKey = "qlaunch.hotkey.configuration"

    static let defaultLaunchpad = HotKeyConfiguration(
        key: "L",
        command: true,
        option: true,
        control: true,
        shift: false
    )

    static let defaultSpotlight = HotKeyConfiguration(
        key: "K",
        command: true,
        option: true,
        control: true,
        shift: false
    )

    var normalized: HotKeyConfiguration {
        var copy = self
        let trimmed = copy.key.trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = trimmed.uppercased()
        copy.key = upper.isEmpty ? "L" : String(upper.prefix(1))
        return copy
    }

    var displayText: String {
        var tokens: [String] = []
        if control { tokens.append("⌃") }
        if option { tokens.append("⌥") }
        if shift { tokens.append("⇧") }
        if command { tokens.append("⌘") }
        tokens.append(normalized.key)
        return tokens.joined()
    }
}

struct HotKeySettings: Codable, Equatable {
    var launchpad: HotKeyConfiguration
    var spotlight: HotKeyConfiguration

    static let storageKey = "qlaunch.hotkey.settings"

    static let defaultValue = HotKeySettings(
        launchpad: .defaultLaunchpad,
        spotlight: .defaultSpotlight
    )

    var normalized: HotKeySettings {
        HotKeySettings(
            launchpad: launchpad.normalized,
            spotlight: spotlight.normalized
        )
    }

    var hasConflict: Bool {
        launchpad.normalized == spotlight.normalized
    }
}

@MainActor
final class HotKeySettingsStore: ObservableObject {
    static let shared = HotKeySettingsStore()

    @Published private(set) var settings: HotKeySettings

    private init() {
        if let data = UserDefaults.standard.data(forKey: HotKeySettings.storageKey),
           let decoded = try? JSONDecoder().decode(HotKeySettings.self, from: data) {
            settings = decoded.normalized
            return
        }

        // Backward compatibility for the older single-hotkey schema.
        if let data = UserDefaults.standard.data(forKey: HotKeyConfiguration.legacyStorageKey),
           let decoded = try? JSONDecoder().decode(HotKeyConfiguration.self, from: data) {
            settings = HotKeySettings(
                launchpad: decoded.normalized,
                spotlight: .defaultSpotlight
            )
            persist(settings)
            UserDefaults.standard.removeObject(forKey: HotKeyConfiguration.legacyStorageKey)
            return
        }

        settings = .defaultValue
    }

    func update(settings: HotKeySettings) {
        let normalized = settings.normalized
        guard normalized != self.settings else {
            return
        }

        self.settings = normalized
        persist(normalized)
    }

    func reset() {
        update(settings: .defaultValue)
    }

    private func persist(_ settings: HotKeySettings) {
        if let encoded = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(encoded, forKey: HotKeySettings.storageKey)
        }
    }
}
