import SwiftUI

/// The fast answer. Japanese large, English and price on the row, everything
/// else one tap below — progressive disclosure means the tourist never has
/// to go deeper.
struct ResultListView: View {
    let parse: MenuParse

    private let enrichment = EnrichmentStore.shared

    var body: some View {
        List {
            ForEach(parse.sections) { section in
                Section {
                    ForEach(section.items) { item in
                        NavigationLink(value: item) {
                            MenuItemRow(item: item, enrichment: enrichment.enrichment(for: item))
                        }
                    }
                } header: {
                    if let header = section.headerJa {
                        sectionHeader(header, english: enrichment.sectionEnglish(header))
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Menu")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text("Menu").font(.headline)
                    Text("\(parse.allItems.count) items · \(parse.sections.count) sections")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        // Row taps resolve against the MenuItem destination declared on the
        // NavigationStack in CaptureView.
    }

    private func sectionHeader(_ header: String, english: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(header)
                .font(.headline.weight(.heavy))
                .foregroundStyle(Color(red: 0.89, green: 0.34, blue: 0.23))
            if let english {
                Text(english)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
        }
        .padding(.top, 8)
    }
}

struct MenuItemRow: View {
    let item: MenuItem
    let enrichment: DishEnrichment?

    var body: some View {
        HStack(spacing: 12) {
            DishThumbnail(photoName: enrichment?.photo, size: 52)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.nameJa)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if item.confidence.needsMarker {
                        // Never present a guess as authoritative.
                        Image(systemName: "questionmark.circle")
                            .font(.caption)
                            .foregroundStyle(item.confidence == .low ? .orange : .secondary)
                    }
                }
                if let english = enrichment?.english {
                    Text(english)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let note = item.noteJa {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if let priceLabel = item.priceLabel {
                Text(priceLabel)
                    .font(.body.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color(red: 0.95, green: 0.71, blue: 0.27))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.vertical, 4)
    }
}

struct DishThumbnail: View {
    let photoName: String?
    var size: CGFloat = 52

    var body: some View {
        Group {
            if let image = EnrichmentStore.shared.photo(named: photoName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.fill.quaternary)
                    .overlay {
                        Image(systemName: "fork.knife")
                            .font(.system(size: size * 0.36))
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
