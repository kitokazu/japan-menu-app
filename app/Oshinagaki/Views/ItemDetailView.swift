import SwiftData
import SwiftUI

/// One layer below the fast answer: this is where Sam's depth lives.
/// Reading, romaji, translation, description and kanji breakdown arrive with
/// the language layer (dictionary + enrichment); the layout stakes out their
/// place now so the screen structure is settled early.
struct ItemDetailView: View {
    let item: MenuItem

    @Environment(\.modelContext) private var modelContext
    @Query private var saved: [SavedItem]
    @State private var showOrderingMode = false

    private var isSaved: Bool {
        saved.contains { $0.nameJa == item.nameJa }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if item.confidence.needsMarker {
                    confidenceCallout
                }

                placeholderSection(
                    title: "Reading",
                    detail: "Furigana, hiragana and romaji come from the curated food dictionary (Phase 2)."
                )
                placeholderSection(
                    title: "What is this?",
                    detail: "The one-or-two-sentence description of the actual dish arrives with the enrichment backend."
                )
                placeholderSection(
                    title: "Kanji breakdown",
                    detail: "Per-character meaning and common readings (Phase 2)."
                )

                orderingButton
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.nameJa)
                .font(.system(size: 40, weight: .bold))
            if let note = item.noteJa {
                Text(note)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            if let priceLabel = item.priceLabel {
                Text(priceLabel)
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.secondary)
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
            Label("Order this", systemImage: "hand.point.up.left")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
    }

    private func toggleSaved() {
        if let existing = saved.first(where: { $0.nameJa == item.nameJa }) {
            modelContext.delete(existing)
        } else {
            modelContext.insert(SavedItem(nameJa: item.nameJa, noteJa: item.noteJa, price: item.price))
        }
    }
}
