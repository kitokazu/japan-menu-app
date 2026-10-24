import AVFoundation
import SwiftUI

/// Full-screen, maximum-size Japanese, designed to be read aloud or pointed
/// at. Cheap to build, disproportionately valuable — do not cut.
struct OrderingModeView: View {
    let item: MenuItem

    @Environment(\.dismiss) private var dismiss
    @State private var synthesizer = AVSpeechSynthesizer()

    private var enrichment: DishEnrichment? { EnrichmentStore.shared.enrichment(for: item) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 28) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    Spacer()
                    Text("ORDERING MODE")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.gray)
                        .kerning(1.5)
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 12)

                Spacer()

                if let enrichment {
                    FuriganaText(
                        segments: enrichment.segments,
                        baseSize: 58,
                        weight: .black,
                        alignment: .center,
                        baseColor: .white,
                        rubyColor: .gray
                    )
                    .padding(.horizontal, 20)

                    FuriganaText(
                        segments: [ReadingSegment(t: "一", r: "ひと"), ReadingSegment(t: "つください", r: nil)],
                        baseSize: 30,
                        weight: .bold,
                        alignment: .center,
                        baseColor: Color(white: 0.8),
                        rubyColor: .gray
                    )

                    VStack(spacing: 6) {
                        Text("\(enrichment.romaji), hitotsu kudasai")
                            .font(.headline)
                            .foregroundStyle(Color(red: 0.95, green: 0.71, blue: 0.27))
                        Text("\u{201C}One \(enrichment.english.lowercased()), please.\u{201D}")
                            .font(.subheadline)
                            .foregroundStyle(.gray)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                } else {
                    Text(item.nameJa)
                        .font(.system(size: 64, weight: .bold))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.4)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Text("これをください")
                        .font(.title2)
                        .foregroundStyle(.gray)
                }

                Spacer()

                Button {
                    speak()
                } label: {
                    Label("Say it aloud", systemImage: "speaker.wave.2.fill")
                        .font(.title3.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.89, green: 0.34, blue: 0.23))
                .padding(.horizontal, 24)

                Text("Or turn the phone toward the staff and point.")
                    .font(.footnote)
                    .foregroundStyle(.gray)
                    .padding(.bottom, 16)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func speak() {
        // Speak the curated kana reading when we have one, so the synthesizer
        // never guesses a kanji reading (鮟鱇, 湯葉 and friends are irregular).
        let spoken = enrichment?.reading ?? item.nameJa
        let utterance = AVSpeechUtterance(string: "\(spoken)を一つください")
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        utterance.rate = 0.45
        synthesizer.speak(utterance)
    }
}
