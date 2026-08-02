import AVFoundation
import SwiftUI

/// Full-screen, maximum-size Japanese, designed to be read aloud or pointed
/// at. Cheap to build, disproportionately valuable — do not cut.
struct OrderingModeView: View {
    let item: MenuItem

    @Environment(\.dismiss) private var dismiss
    @State private var synthesizer = AVSpeechSynthesizer()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // TODO(Phase 2): furigana rendered above the kanji once the
                // curated dictionary provides readings.
                Text(item.nameJa)
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.4)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if let note = item.noteJa {
                    Text(note)
                        .font(.title3)
                        .foregroundStyle(.gray)
                }

                Text("これをください")
                    .font(.title2)
                    .foregroundStyle(.gray)

                Spacer()

                Button {
                    speak()
                } label: {
                    Label("Play", systemImage: "speaker.wave.2.fill")
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.15))

                Button("Done") { dismiss() }
                    .foregroundStyle(.gray)
                    .padding(.bottom, 24)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func speak() {
        // ja-JP synthesis reads kanji with its own reading model; good enough
        // until the curated dictionary supplies authoritative readings.
        let utterance = AVSpeechUtterance(string: "\(item.nameJa)をください")
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        utterance.rate = 0.45
        synthesizer.speak(utterance)
    }
}
