import Foundation

struct LaunchpadPagination {
    let page: Int
    let totalPages: Int
    let items: [LaunchpadApp]
}

enum LaunchpadCore {
    static let iconsPerPage = 35

    static func normalizeQuery(_ query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let folded = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return folded.lowercased()
    }

    static func filter(apps: [LaunchpadApp], query: String) -> [LaunchpadApp] {
        let normalized = normalizeQuery(query)
        guard !normalized.isEmpty else {
            return apps
        }

        let queryTokens = queryVariants(for: normalized)

        return apps.filter { app in
            let candidates = appSearchCandidates(for: app)
            return queryTokens.contains { token in
                candidates.contains { candidate in
                    matches(token: token, candidate: candidate)
                }
            }
        }
    }

    static func pageSize(for size: CGSize) -> Int {
        _ = size
        return iconsPerPage
    }

    static func pageCount(totalItems: Int, pageSize: Int) -> Int {
        guard totalItems > 0 else {
            return 1
        }

        return max(1, Int(ceil(Double(totalItems) / Double(max(pageSize, 1)))))
    }

    static func clamp(page: Int, totalPages: Int) -> Int {
        guard totalPages > 0 else {
            return 0
        }

        return min(max(page, 0), totalPages - 1)
    }

    static func paginate(apps: [LaunchpadApp], page: Int, pageSize: Int) -> LaunchpadPagination {
        let safePageSize = max(pageSize, 1)
        let totalPages = pageCount(totalItems: apps.count, pageSize: safePageSize)
        let currentPage = clamp(page: page, totalPages: totalPages)
        let start = currentPage * safePageSize
        let end = min(start + safePageSize, apps.count)

        guard start < end else {
            return LaunchpadPagination(page: currentPage, totalPages: totalPages, items: [])
        }

        return LaunchpadPagination(page: currentPage, totalPages: totalPages, items: Array(apps[start..<end]))
    }

    private static func queryVariants(for normalizedQuery: String) -> [String] {
        var variants = Set<String>()
        variants.insert(normalizedQuery)
        variants.insert(normalizedQuery.replacingOccurrences(of: " ", with: ""))

        let latinizedQuery = latinized(normalizedQuery)
        if !latinizedQuery.isEmpty {
            variants.insert(latinizedQuery)
            variants.insert(latinizedQuery.replacingOccurrences(of: " ", with: ""))
        }

        return variants.filter { !$0.isEmpty }
    }

    private static func appSearchCandidates(for app: LaunchpadApp) -> [String] {
        var candidates = Set<String>()

        let normalizedName = normalizeQuery(app.name)
        candidates.insert(normalizedName)
        candidates.insert(normalizedName.replacingOccurrences(of: " ", with: ""))

        let pinyinName = latinized(app.name)
        if !pinyinName.isEmpty {
            candidates.insert(pinyinName)
            candidates.insert(pinyinName.replacingOccurrences(of: " ", with: ""))
        }

        if let bundleIdentifier = app.bundleIdentifier {
            candidates.insert(normalizeQuery(bundleIdentifier))
        }

        return candidates.filter { !$0.isEmpty }
    }

    private static func matches(token: String, candidate: String) -> Bool {
        guard !token.isEmpty, !candidate.isEmpty else {
            return false
        }

        if candidate.contains(token) {
            return true
        }

        return isSubsequence(token, in: candidate)
    }

    private static func isSubsequence(_ token: String, in candidate: String) -> Bool {
        guard token.count <= candidate.count else {
            return false
        }

        var candidateIndex = candidate.startIndex
        for tokenCharacter in token {
            var found = false

            while candidateIndex < candidate.endIndex {
                if candidate[candidateIndex] == tokenCharacter {
                    found = true
                    candidate.formIndex(after: &candidateIndex)
                    break
                }
                candidate.formIndex(after: &candidateIndex)
            }

            if !found {
                return false
            }
        }

        return true
    }

    private static func latinized(_ text: String) -> String {
        guard !text.isEmpty else {
            return ""
        }

        let mutable = NSMutableString(string: text) as CFMutableString
        CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripCombiningMarks, false)

        let transformed = (mutable as String).lowercased()
        let collapsedWhitespace = transformed
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        return collapsedWhitespace
    }
}
