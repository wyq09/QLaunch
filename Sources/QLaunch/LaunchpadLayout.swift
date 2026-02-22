import Foundation

struct LaunchpadFolder: Identifiable, Hashable {
    let id: UUID
    var name: String
    var appIDs: [String]

    init(id: UUID = UUID(), name: String = "新建文件夹", appIDs: [String]) {
        self.id = id
        self.name = name
        self.appIDs = appIDs
    }
}

enum LaunchpadItem: Identifiable, Hashable {
    case app(appID: String)
    case folder(LaunchpadFolder)

    var id: String {
        switch self {
        case .app(let appID):
            return "app:\(appID)"
        case .folder(let folder):
            return "folder:\(folder.id.uuidString)"
        }
    }
}

enum LaunchpadDropTarget: Hashable {
    case app(String)
    case folder(UUID)
    case folderExtraction(UUID)
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else {
            return [self]
        }

        var result: [[Element]] = []
        result.reserveCapacity((count + size - 1) / size)

        var index = 0
        while index < count {
            let end = Swift.min(index + size, count)
            result.append(Array(self[index..<end]))
            index += size
        }

        return result
    }
}
