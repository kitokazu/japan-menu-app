import Foundation
import UIKit

/// The language layer for one dish: what the curated dictionary and the
/// enrichment backend will eventually return per `name_ja`.
///
/// Keyed by the exact printed name, which is also how the production
/// dish-level cache is keyed (PRD §7): 焼き鳥 is enriched once, ever.
struct DishEnrichment: Codable, Hashable {
    var english: String
    var reading: String
    var romaji: String
    var description: String
    var photo: String?
    var segments: [ReadingSegment]
}

/// One run of text with its furigana. `reading` is nil for kana runs.
struct ReadingSegment: Codable, Hashable {
    var t: String
    var r: String?

    var text: String { t }
    var reading: String? { r }
}

struct KanjiEntry: Codable, Hashable {
    var meaning: String
    /// Kun reading in hiragana, okurigana in parentheses: つ(ける)
    var kun: String?
    /// On reading in katakana: シ
    var on: String?
    var kunRomaji: String?
    var onRomaji: String?
    /// Concept photo resource name (bundled JPEG), if one exists.
    var photo: String?
    var photoCredit: String?

    enum CodingKeys: String, CodingKey {
        case meaning, kun, on, photo
        case kunRomaji = "kun_romaji"
        case onRomaji = "on_romaji"
        case photoCredit = "photo_credit"
    }

    /// Compact "かい · バイ" form for the tiles.
    var readings: String {
        [kun, on].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Bundled stand-in for the dictionary + enrichment service. Same seam idea
/// as `FixtureParseService`: swap the source, keep the views.
final class EnrichmentStore {
    static let shared = EnrichmentStore()

    private struct Payload: Codable {
        var sections: [String: String]
        var items: [String: DishEnrichment]
        var kanji: [String: KanjiEntry]
    }

    private let payload: Payload
    private var imageCache: [String: UIImage] = [:]

    private init() {
        if let url = Bundle.main.url(forResource: "fixture_enrichment", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(Payload.self, from: data) {
            payload = decoded
        } else {
            payload = Payload(sections: [:], items: [:], kanji: [:])
        }
    }

    func enrichment(for item: MenuItem) -> DishEnrichment? {
        payload.items[item.nameJa]
    }

    func sectionEnglish(_ headerJa: String?) -> String? {
        guard let headerJa else { return nil }
        return payload.sections[headerJa]
    }

    /// Each distinct kanji in the name, in order of first appearance.
    func kanjiBreakdown(for nameJa: String) -> [(character: String, entry: KanjiEntry)] {
        var seen = Set<Character>()
        var result: [(String, KanjiEntry)] = []
        for character in nameJa where !seen.contains(character) {
            if let entry = payload.kanji[String(character)] {
                seen.insert(character)
                result.append((String(character), entry))
            }
        }
        return result
    }

    func photo(named name: String?) -> UIImage? {
        guard let name else { return nil }
        if let cached = imageCache[name] { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg"),
              let image = UIImage(contentsOfFile: url.path)
        else { return nil }
        imageCache[name] = image
        return image
    }
}
