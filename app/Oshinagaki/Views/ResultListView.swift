import SwiftUI

/// The fast answer. Japanese large, price on the row, everything else one tap
/// below — progressive disclosure means the tourist never has to go deeper.
struct ResultListView: View {
    let parse: MenuParse

    var body: some View {
        List {
            ForEach(parse.sections) { section in
                Section {
                    ForEach(section.items) { item in
                        NavigationLink(value: item) {
                            MenuItemRow(item: item)
                        }
                    }
                } header: {
                    if let header = section.headerJa {
                        Text(header)
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
        .navigationTitle("Menu")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: MenuItem.self) { item in
            ItemDetailView(item: item)
        }
    }
}

struct MenuItemRow: View {
    let item: MenuItem

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.nameJa)
                        .font(.title3.weight(.medium))
                    if item.confidence.needsMarker {
                        // Never present a guess as authoritative.
                        Image(systemName: "questionmark.circle")
                            .font(.caption)
                            .foregroundStyle(item.confidence == .low ? .orange : .secondary)
                    }
                }
                if let note = item.noteJa {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let priceLabel = item.priceLabel {
                Text(priceLabel)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
