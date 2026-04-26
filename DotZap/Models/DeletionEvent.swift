import Foundation

struct DeletionEvent: Codable, Identifiable, Hashable {
    var id: UUID
    var path: String
    var ruleName: String
    var bytes: Int
    var volumeName: String
    var timestamp: Date

    var fileName: String {
        (path as NSString).lastPathComponent
    }

    init(
        id: UUID = UUID(),
        path: String,
        ruleName: String,
        bytes: Int,
        volumeName: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.path = path
        self.ruleName = ruleName
        self.bytes = bytes
        self.volumeName = volumeName
        self.timestamp = timestamp
    }
}
