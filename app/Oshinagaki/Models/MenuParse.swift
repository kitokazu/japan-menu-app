import Foundation

/// The parse result contract.
///
/// This mirrors `MENU_SCHEMA` in `benchmark/scripts/run_parse.py` exactly —
/// the backend will return this shape, and the benchmark validates models
/// against it. If one side changes, change the other.
struct MenuParse: Codable, Hashable {
    var sections: [MenuSection]
    var decorativeText: [String]

    enum CodingKeys: String, CodingKey {
        case sections
        case decorativeText = "decorative_text"
    }

    var allItems: [MenuItem] {
        sections.flatMap(\.items)
    }
}

struct MenuSection: Codable, Hashable, Identifiable {
    var id = UUID()
    var headerJa: String?
    var items: [MenuItem]

    enum CodingKeys: String, CodingKey {
        case headerJa = "header_ja"
        case items
    }
}

struct MenuItem: Codable, Hashable, Identifiable {
    var id = UUID()
    var nameJa: String
    var noteJa: String?
    var price: Int?
    var priceNote: String?
    var confidence: Confidence

    enum CodingKeys: String, CodingKey {
        case nameJa = "name_ja"
        case noteJa = "note_ja"
        case price
        case priceNote = "price_note"
        case confidence
    }

    var priceLabel: String? {
        guard let price else { return nil }
        let formatted = "¥\(price.formatted(.number.grouping(.automatic)))"
        if let priceNote { return "\(formatted) \(priceNote)" }
        return formatted
    }
}

enum Confidence: String, Codable, Hashable {
    case high, medium, low

    /// "Wrong is worse than absent": anything below high carries a visible
    /// marker so a guess is never presented as authoritative.
    var needsMarker: Bool { self != .high }
}
