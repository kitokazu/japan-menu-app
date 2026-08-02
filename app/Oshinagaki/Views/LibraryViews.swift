import SwiftData
import SwiftUI

struct SavedItemsView: View {
    @Query(sort: \SavedItem.savedAt, order: .reverse) private var items: [SavedItem]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView(
                        "Nothing saved yet",
                        systemImage: "star",
                        description: Text("Star a dish on its detail screen to keep it here.")
                    )
                } else {
                    List {
                        ForEach(items) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.nameJa)
                                    .font(.title3.weight(.medium))
                                if let note = item.noteJa {
                                    Text(note)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { offsets in
                            for offset in offsets {
                                modelContext.delete(items[offset])
                            }
                        }
                    }
                }
            }
            .navigationTitle("Saved")
        }
    }
}

struct HistoryView: View {
    @Query(sort: \ScanRecord.scannedAt, order: .reverse) private var scans: [ScanRecord]

    var body: some View {
        NavigationStack {
            Group {
                if scans.isEmpty {
                    ContentUnavailableView(
                        "No scans yet",
                        systemImage: "clock",
                        description: Text("Scanned menus show up here so you can find that place you went last month.")
                    )
                } else {
                    List(scans) { scan in
                        HStack(spacing: 12) {
                            thumbnailView(scan.thumbnail)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(scan.scannedAt, style: .date)
                                    .font(.body.weight(.medium))
                                Text("\(scan.itemCount) items")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
        }
    }

    @ViewBuilder
    private func thumbnailView(_ data: Data?) -> some View {
        if let data, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(.fill.quaternary)
                .frame(width: 48, height: 48)
                .overlay {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.tertiary)
                }
        }
    }
}
