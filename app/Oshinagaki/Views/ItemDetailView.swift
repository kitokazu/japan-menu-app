import SwiftData
import SwiftUI

struct KanjiSelection: Identifiable {
    let id: String
    let entry: KanjiEntry
}

/// One layer below the fast answer: this is where Sam's depth lives.
/// Reading, romaji, translation, description and kanji breakdown come from
/// `EnrichmentStore` (bundled fixture now, dictionary + backend later).
struct ItemDetailView: View {
    let item: MenuItem

    @Environment(\.modelContext) private var modelContext
    @Query private var saved: [SavedItem]
    @State private var showOrderingMode = false
    @State private var selectedKanji: KanjiSelection?

    private let store = EnrichmentStore.shared
    private var enrichment: DishEnrichment? { store.enrichment(for: item) }

    private var isSaved: Bool {
        saved.contains { $0.nameJa == item.nameJa }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let image = store.photo(named: enrichment?.photo) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                header

                if item.confidence.needsMarker {
                    confidenceCallout
                }

                if let enrichment {
                    descriptionCard(enrichment)
                    kanjiSection
                } else {
                    placeholderSection(
                        title: "What is this?",
                        detail: "Not in the dictionary yet. The description arrives with the enrichment backend."
                    )
                }

                orderingButton
                photosLink
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button {
                toggleSaved()
            } label: {
                Image(systemName: isSaved ? "star.fill" : "star")
                    .foregroundStyle(isSaved ? .yellow : .primary)
            }
        }
        .fullScreenCover(isPresented: $showOrderingMode) {
            OrderingModeView(item: item)
        }
        .sheet(item: $selectedKanji) { selection in
            KanjiDetailView(character: selection.id, entry: selection.entry, contextName: item.nameJa)
        }
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            // `-openOrdering` launch argument: jump straight to ordering mode.
            if args.contains("-openOrdering") {
                showOrderingMode = true
            }
            // `-openKanji 貝`: open that kanji's sheet.
            if let index = args.firstIndex(of: "-openKanji"), index + 1 < args.count,
               let match = store.kanjiBreakdown(for: item.nameJa).first(where: { $0.character == args[index + 1] }) {
                selectedKanji = KanjiSelection(id: match.character, entry: match.entry)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let enrichment {
                FuriganaText(segments: enrichment.segments, baseSize: 34)
                HStack(spacing: 10) {
                    Text(enrichment.reading)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(enrichment.romaji)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.tertiary)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(enrichment.english)
                        .font(.title2.weight(.bold))
                    Spacer()
                    if let priceLabel = item.priceLabel {
                        Text(priceLabel)
                            .font(.title2.weight(.bold).monospacedDigit())
                            .foregroundStyle(Color(red: 0.95, green: 0.71, blue: 0.27))
                    }
                }
            } else {
                Text(item.nameJa)
                    .font(.system(size: 36, weight: .bold))
                if let priceLabel = item.priceLabel {
                    Text(priceLabel)
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if let note = item.noteJa {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func descriptionCard(_ enrichment: DishEnrichment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("What it is")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                // Curated entries show clean; model-generated ones would carry
                // an "auto" marker instead (PRD §8).
                Text("Curated")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .overlay(Capsule().stroke(.green.opacity(0.6)))
            }
            Text(enrichment.description)
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var kanjiSection: some View {
        let breakdown = store.kanjiBreakdown(for: item.nameJa)
        if !breakdown.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Kanji")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(breakdown, id: \.character) { entry in
                        Button {
                            selectedKanji = KanjiSelection(id: entry.character, entry: entry.entry)
                        } label: {
                            VStack(spacing: 4) {
                                Text(entry.character)
                                    .font(.system(size: 30, weight: .bold))
                                    .foregroundStyle(.primary)
                                Text(entry.entry.meaning)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                Text(entry.entry.readings)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 6)
                            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Tap a character for its photo and readings.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var confidenceCallout: some View {
        Label(
            item.confidence == .low
                ? "This name may be misread — confirm with staff before relying on it."
                : "One or more characters in this name are uncertain.",
            systemImage: "exclamationmark.triangle"
        )
        .font(.footnote)
        .foregroundStyle(.orange)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private func placeholderSection(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    private var orderingButton: some View {
        Button {
            showOrderingMode = true
        } label: {
            Label("Order this", systemImage: "speaker.wave.2.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color(red: 0.89, green: 0.34, blue: 0.23))
    }

    /// V1 stopgap for dish images (PRD §6.8): deep-link to an image search.
    private var photosLink: some View {
        let query = item.nameJa.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return Link(destination: URL(string: "https://www.google.com/search?tbm=isch&q=\(query)")!) {
            Label("See more photos", systemImage: "photo.on.rectangle.angled")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.bordered)
    }

    private func toggleSaved() {
        if let existing = saved.first(where: { $0.nameJa == item.nameJa }) {
            modelContext.delete(existing)
        } else {
            modelContext.insert(SavedItem(nameJa: item.nameJa, noteJa: item.noteJa, price: item.price))
        }
    }
}
