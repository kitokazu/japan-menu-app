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
    @State private var result: MenuParse?

    var body: some View {
        NavigationStack {
            ZStack {
                if camera.isAvailable {
                    CameraPreview(session: camera.session)
                        .ignoresSafeArea()
                } else {
                    ContentUnavailableView(
                        "Camera unavailable",
                        systemImage: "camera.on.rectangle",
                        description: Text("Use the photo library button below — the simulator has no camera.")
                    )
                }

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
            .navigationDestination(item: $result) { parse in
                ResultListView(parse: parse)
            }
            .task { await camera.start() }
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
            .disabled(!camera.isAvailable || isParsing)
            .opacity(camera.isAvailable ? 1 : 0.3)

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
        do {
            let data = try await camera.capturePhoto()
            await parse(imageData: data)
        } catch {
            errorMessage = "Couldn't take the photo. Try again."
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

    private func parse(imageData: Data) async {
        isParsing = true
        defer { isParsing = false }

        guard await TextPrecheck.containsText(imageData: imageData) else {
            errorMessage = ParseError.noTextFound.localizedDescription
            return
        }

        do {
            let parse = try await parseService.parse(imageData: imageData)
            recordScan(parse: parse, imageData: imageData)
            result = parse
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
