import Foundation

struct LaunchpadApp: Identifiable, Hashable {
    let url: URL
    let name: String
    let bundleIdentifier: String?

    var id: String {
        url.path
    }
}
