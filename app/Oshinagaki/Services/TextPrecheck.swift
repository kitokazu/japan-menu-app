import Foundation
@preconcurrency import Vision

/// On-device pre-check: reject "no text found" before spending an API call.
///
/// This is deliberately permissive — its job is to catch pocket shots and
/// blurry nothing, not to judge readability. A false "has text" costs one API
/// call; a false "no text" blocks a legitimate scan.
enum TextPrecheck {
    static func containsText(imageData: Data) async -> Bool {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                continuation.resume(returning: !observations.isEmpty)
            }
            // Fast path is fine here: we only need existence, not accuracy.
            request.recognitionLevel = .fast
            request.recognitionLanguages = ["ja-JP", "en-US"]

            let handler = VNImageRequestHandler(data: imageData)
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    // If Vision itself fails, let the scan through rather than
                    // blocking the user on a pre-check.
                    continuation.resume(returning: true)
                }
            }
        }
    }
}
