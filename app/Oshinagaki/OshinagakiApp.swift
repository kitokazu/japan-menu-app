import SwiftUI
import SwiftData

@main
struct OshinagakiApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                // Dark-first: the design target is a dim izakaya basement.
                .preferredColorScheme(.dark)
        }
        .modelContainer(for: [SavedItem.self, ScanRecord.self])
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            CaptureView()
                .tabItem { Label("Scan", systemImage: "camera.viewfinder") }
            SavedItemsView()
                .tabItem { Label("Saved", systemImage: "star") }
            HistoryView()
                .tabItem { Label("History", systemImage: "clock") }
        }
    }
}
