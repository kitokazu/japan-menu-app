import Foundation
import SwiftData

/// A dish the user starred. Local-only in V1 — no account, no sync.
@Model
final class SavedItem {
    var nameJa: String
    var noteJa: String?
    var price: Int?
    var savedAt: Date

    init(nameJa: String, noteJa: String? = nil, price: Int? = nil, savedAt: Date = .now) {
        self.nameJa = nameJa
        self.noteJa = noteJa
        self.price = price
        self.savedAt = savedAt
    }
}

/// One scan: when, how many items, and a thumbnail to find that place again.
@Model
final class ScanRecord {
    var scannedAt: Date
    var itemCount: Int
    @Attribute(.externalStorage) var thumbnail: Data?

    init(scannedAt: Date = .now, itemCount: Int, thumbnail: Data? = nil) {
        self.scannedAt = scannedAt
        self.itemCount = itemCount
        self.thumbnail = thumbnail
    }
}
