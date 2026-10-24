import PhotosUI
import SwiftData
import SwiftUI

struct CaptureView: View {
    @StateObject private var camera = CameraController()
    @Environment(\.modelContext) private var modelContext

    // Swap for BackendParseService once the benchmark picks a model.
    private let parseService: ParseService = FixtureParseService()

    @State private var pickedItem: PhotosPickerItem?
    @State private var isParsing = false
    @State private var errorMessage: String?
    /// Navigation: [MenuParse] for the result list, then [MenuItem] for a
    /// dish detail. One stack, one path, so programmatic pushes (the
    /// `-openItem` flag) and row taps go through the same destinations.
    @State private var path = NavigationPath()

    /// Bundled menu photo shown in the viewfinder when there is no camera
    /// (the Simulator), so the shutter still demos the whole flow.
    private let sampleMenu: UIImage? = {
        guard let url = Bundle.main.url(forResource: "sample_menu", withExtension: "jpg") else { return nil }
        return UIImage(contentsOfFile: url.path)
    }()

    private var shutterEnabled: Bool {
        (camera.isAvailable || sampleMenu != nil) && !isParsing
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                if camera.isAvailable {
                    CameraPreview(session: camera.session)
                        .ignoresSafeArea()
                } else if let sampleMenu {
                    Image(uiImage: sampleMenu)
                        .resizable()
                        .scaledToFill()
                        .ignoresSafeArea()
                        .overlay(alignment: .top) {
                            Text("Sample menu · no camera in the Simulator")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.black.opacity(0.65), in: Capsule())
                                .padding(.top, 8)
                        }
                } else {
                    ContentUnavailableView(
                        "Camera unavailable",
                        systemImage: "camera.on.rectangle",
                        description: Text("Use the photo library button below.")
                    )
                }

                viewfinderCorners

                VStack {
                    Spacer()
                    controls
                }

                if isParsing {
                    parsingOverlay
                }
            }
            .navigationTitle("お品書き")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: MenuParse.self) { parse in
                ResultListView(parse: parse)
            }
            .navigationDestination(for: MenuItem.self) { item in
                ItemDetailView(item: item)
            }
            .task {
                await camera.start()
                // `-autoScan` launch argument: scan the sample immediately
                // (used for screenshots and smoke tests in the Simulator).
                if ProcessInfo.processInfo.arguments.contains("-autoScan") {
                    await captureAndParse()
                }
            }
            .onDisappear { camera.stop() }
            .onChange(of: pickedItem) { _, item in
                guard let item else { return }
                Task { await handlePickedItem(item) }
            }
            .alert("Scan failed", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var viewfinderCorners: some View {
        GeometryReader { proxy in
            let inset: CGFloat = 28
            let rect = CGRect(
                x: inset,
                y: proxy.size.height * 0.16,
                width: proxy.size.width - inset * 2,
                height: proxy.size.height * 0.56
            )
            ViewfinderCorners(rect: rect)
                .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .opacity(camera.isAvailable || sampleMenu != nil ? 0.9 : 0)
        }
        .allowsHitTesting(false)
    }

    private var controls: some View {
        HStack(spacing: 44) {
            PhotosPicker(selection: $pickedItem, matching: .images) {
                Image(systemName: "photo.on.rectangle")
                    .font(.title2)
                    .frame(width: 56, height: 56)
                    .background(.ultraThinMaterial, in: Circle())
            }

            Button {
                Task { await captureAndParse() }
            } label: {
                ZStack {
                    Circle().stroke(.white, lineWidth: 4).frame(width: 76, height: 76)
                    Circle().fill(.white).frame(width: 62, height: 62)
                }
            }
            .disabled(!shutterEnabled)
            .opacity(shutterEnabled ? 1 : 0.3)

            // Torch is prominent by design: izakayas are dark.
            Button {
                camera.toggleTorch()
            } label: {
                Image(systemName: camera.torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                    .font(.title2)
                    .frame(width: 56, height: 56)
                    .background(.ultraThinMaterial, in: Circle())
                    .foregroundStyle(camera.torchOn ? .yellow : .white)
            }
            .disabled(!camera.isAvailable)
            .opacity(camera.isAvailable ? 1 : 0.3)
        }
        .padding(.bottom, 24)
    }

    private var parsingOverlay: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                Text("Reading menu…")
                    .font(.headline)
            }
        }
    }

    private func captureAndParse() async {
        if camera.isAvailable {
            do {
                let data = try await camera.capturePhoto()
                await parse(imageData: data)
            } catch {
                errorMessage = "Couldn't take the photo. Try again."
            }
        } else if let data = sampleMenu?.jpegData(compressionQuality: 0.85) {
            // The bundled sample is known to contain text; skip the pre-check.
            await parse(imageData: data, precheck: false)
        }
    }

    private func handlePickedItem(_ item: PhotosPickerItem) async {
        pickedItem = nil
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            errorMessage = "Couldn't load that photo."
            return
        }
        await parse(imageData: data)
    }

    private func parse(imageData: Data, precheck: Bool = true) async {
        isParsing = true
        defer { isParsing = false }

        if precheck {
            guard await TextPrecheck.containsText(imageData: imageData) else {
                errorMessage = ParseError.noTextFound.localizedDescription
                return
            }
        }

        do {
            let parse = try await parseService.parse(imageData: imageData)
            recordScan(parse: parse, imageData: imageData)
            path.append(parse)
            // `-openItem <name_ja>` launch argument: push that dish too.
            let args = ProcessInfo.processInfo.arguments
            if let index = args.firstIndex(of: "-openItem"), index + 1 < args.count,
               let item = parse.allItems.first(where: { $0.nameJa == args[index + 1] }) {
                path.append(item)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func recordScan(parse: MenuParse, imageData: Data) {
        let thumbnail = UIImage(data: imageData)
            .flatMap { $0.preparingThumbnail(of: CGSize(width: 200, height: 200)) }
            .flatMap { $0.jpegData(compressionQuality: 0.7) }
        modelContext.insert(ScanRecord(itemCount: parse.allItems.count, thumbnail: thumbnail))
    }
}

/// Four L-shaped corner marks around the text-detection region.
struct ViewfinderCorners: Shape {
    let rect: CGRect
    var length: CGFloat = 30

    func path(in _: CGRect) -> Path {
        var path = Path()
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: rect.minX, y: rect.minY), 1, 1),
            (CGPoint(x: rect.maxX, y: rect.minY), -1, 1),
            (CGPoint(x: rect.minX, y: rect.maxY), 1, -1),
            (CGPoint(x: rect.maxX, y: rect.maxY), -1, -1),
        ]
        for (point, dx, dy) in corners {
            path.move(to: CGPoint(x: point.x, y: point.y + dy * length))
            path.addLine(to: point)
            path.addLine(to: CGPoint(x: point.x + dx * length, y: point.y))
        }
        return path
    }
}
