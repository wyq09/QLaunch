import AppKit
import Foundation
import UniformTypeIdentifiers

struct InstalledAppsProvider {
    static let defaultSearchPaths: [URL] = [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        URL(fileURLWithPath: "/Applications/Utilities", isDirectory: true),
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true),
    ]

    static func loadInstalledApps(searchPaths: [URL] = defaultSearchPaths) -> [LaunchpadApp] {
        let fileManager = FileManager.default
        var apps: [LaunchpadApp] = []
        var seenPaths = Set<String>()
        var seenBundleIDs = Set<String>()

        for rootPath in searchPaths where fileManager.fileExists(atPath: rootPath.path) {
            discoverApps(
                in: rootPath,
                fileManager: fileManager,
                apps: &apps,
                seenPaths: &seenPaths,
                seenBundleIDs: &seenBundleIDs
            )
        }

        return apps.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private static func discoverApps(
        in rootPath: URL,
        fileManager: FileManager,
        apps: inout [LaunchpadApp],
        seenPaths: inout Set<String>,
        seenBundleIDs: inout Set<String>
    ) {
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]

        guard let enumerator = fileManager.enumerator(
            at: rootPath,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
            options: options
        ) else {
            return
        }

        for case let candidate as URL in enumerator {
            guard candidate.pathExtension.lowercased() == "app" else {
                continue
            }

            let resolvedURL = candidate.resolvingSymlinksInPath().standardizedFileURL
            let resolvedPath = resolvedURL.path

            guard seenPaths.insert(resolvedPath).inserted else {
                continue
            }

            let bundle = Bundle(url: resolvedURL)
            let bundleID = bundle?.bundleIdentifier?.lowercased()
            if let bundleID {
                guard seenBundleIDs.insert(bundleID).inserted else {
                    continue
                }
            }

            let displayName = displayName(for: resolvedURL, bundle: bundle, fileManager: fileManager)
            apps.append(LaunchpadApp(url: resolvedURL, name: displayName, bundleIdentifier: bundle?.bundleIdentifier))
        }
    }

    private static func displayName(for url: URL, bundle: Bundle?, fileManager: FileManager) -> String {
        if let explicitName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
           !explicitName.isEmpty {
            return explicitName
        }

        if let bundleName = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String,
           !bundleName.isEmpty {
            return bundleName
        }

        let fallback = fileManager.displayName(atPath: url.path)
        if fallback.hasSuffix(".app") {
            return String(fallback.dropLast(4))
        }

        return fallback
    }
}

@MainActor
final class LaunchpadIconProvider {
    static let shared = LaunchpadIconProvider()

    private let cache = NSCache<NSString, NSImage>()
    private let fallbackIcon: NSImage

    private init() {
        let icon = NSWorkspace.shared.icon(for: .application)
        icon.size = NSSize(width: 256, height: 256)
        fallbackIcon = icon
    }

    func icon(for app: LaunchpadApp) -> NSImage {
        let cacheKey = app.id as NSString

        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        let icon = NSWorkspace.shared.icon(forFile: app.url.path)
        icon.size = NSSize(width: 256, height: 256)
        cache.setObject(icon, forKey: cacheKey)
        return icon
    }

    func fallback() -> NSImage {
        fallbackIcon
    }
}

enum LaunchpadAppOpener {
    @MainActor
    static func open(_ app: LaunchpadApp) -> Bool {
        NSWorkspace.shared.open(app.url)
    }
}
