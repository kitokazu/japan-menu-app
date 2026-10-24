import SwiftUI

/// One kanji, one tap deep: a concept photo, the meaning, and both reading
/// families (kun in hiragana, on in katakana) with romaji. This is the
/// "every menu is a free vocabulary lesson" layer.
struct KanjiDetailView: View {
    let character: String
    let entry: KanjiEntry
    /// The dish this kanji was tapped from, for the "seen in" context line.
    let contextName: String

    @Environment(\.dismiss) private var dismiss

    private let store = EnrichmentStore.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let image = store.photo(named: entry.photo) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(alignment: .bottomLeading) {
                                Text(character)
                                    .font(.system(size: 64, weight: .black))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.6), radius: 8)
                                    .padding(16)
                            }
                    } else {
                        Text(character)
                            .font(.system(size: 96, weight: .black))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 16))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.meaning)
                            .font(.title.weight(.bold))
                        Text("Seen in \(contextName)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 10) {
                        if let kun = entry.kun {
                            readingRow(
                                label: "Kun reading",
                                sublabel: "訓読み · Japanese",
                                kana: kun,
                                romaji: entry.kunRomaji
                            )
                        }
                        if let on = entry.on {
                            readingRow(
                                label: "On reading",
                                sublabel: "音読み · Sino-Japanese",
                                kana: on,
                                romaji: entry.onRomaji
                            )
                        }
                    }

                    if let photoCredit = entry.photoCredit, store.photo(named: entry.photo) != nil {
                        Text("Photo: \(photoCredit), Wikimedia Commons")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding()
            }
            .navigationTitle(character)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func readingRow(label: String, sublabel: String, kana: String, romaji: String?) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(sublabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(kana)
                    .font(.title2.weight(.semibold))
                if let romaji {
                    Text(romaji)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color(red: 0.95, green: 0.71, blue: 0.27))
                }
            }
        }
        .padding(14)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}
