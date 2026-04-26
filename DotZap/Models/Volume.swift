import Foundation

struct Volume: Codable, Identifiable, Hashable {
    var mountPath: String
    var name: String
    var filesystem: String
    var isEnabled: Bool
    var isEjected: Bool
    var isNetwork: Bool
    var whitelist: [String]
    var lifetimeFilesDeleted: Int
    var lifetimeBytesFreed: Int
    var lastSeenAt: Date

    var id: String { mountPath }

    init(
        mountPath: String,
        name: String,
        filesystem: String,
        isEnabled: Bool = true,
        isEjected: Bool = false,
        isNetwork: Bool = false,
        whitelist: [String] = [],
        lifetimeFilesDeleted: Int = 0,
        lifetimeBytesFreed: Int = 0,
        lastSeenAt: Date = Date()
    ) {
        self.mountPath = mountPath
        self.name = name
        self.filesystem = filesystem
        self.isEnabled = isEnabled
        self.isEjected = isEjected
        self.isNetwork = isNetwork
        self.whitelist = whitelist
        self.lifetimeFilesDeleted = lifetimeFilesDeleted
        self.lifetimeBytesFreed = lifetimeBytesFreed
        self.lastSeenAt = lastSeenAt
    }
}
