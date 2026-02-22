import Foundation

struct HotKeyConfiguration: Codable, Equatable {
    var key: String
    var command: Bool
    var option: Bool
    var control: Bool
    var shift: Bool

    static let storageKey = "qlaunch.hotkey.configuration"

    static let defaultValue = HotKeyConfiguration(
        key: "L",
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

@MainActor
final class HotKeySettingsStore: ObservableObject {
    static let shared = HotKeySettingsStore()

    @Published private(set) var configuration: HotKeyConfiguration

    private init() {
        if let data = UserDefaults.standard.data(forKey: HotKeyConfiguration.storageKey),
           let decoded = try? JSONDecoder().decode(HotKeyConfiguration.self, from: data) {
            configuration = decoded.normalized
        } else {
            configuration = .defaultValue
        }
    }

    func update(configuration: HotKeyConfiguration) {
        let normalized = configuration.normalized
        guard normalized != self.configuration else {
            return
        }

        self.configuration = normalized

        if let encoded = try? JSONEncoder().encode(normalized) {
            UserDefaults.standard.set(encoded, forKey: HotKeyConfiguration.storageKey)
        }
    }
}
