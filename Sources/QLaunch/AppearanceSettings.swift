import Foundation

@MainActor
final class AppearanceSettingsStore: ObservableObject {
    static let shared = AppearanceSettingsStore()

    static let storageKey = "qlaunch.appearance.surfaceOpacity"
    static let minOpacity = 0.10
    static let maxOpacity = 1.0
    static let defaultOpacity = 0.82

    @Published private(set) var surfaceOpacity: Double

    private init() {
        let storedOpacity = UserDefaults.standard.object(forKey: Self.storageKey) as? Double
        surfaceOpacity = Self.clamp(storedOpacity ?? Self.defaultOpacity)
    }

    func update(opacity: Double) {
        let clamped = Self.clamp(opacity)
        guard clamped != surfaceOpacity else {
            return
        }

        surfaceOpacity = clamped
        UserDefaults.standard.set(clamped, forKey: Self.storageKey)
    }

    func reset() {
        update(opacity: Self.defaultOpacity)
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, minOpacity), maxOpacity)
    }
}
