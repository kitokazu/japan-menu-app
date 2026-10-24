import SwiftUI

/// Japanese text with furigana rendered above each kanji run.
///
/// Kana runs are split per character so long names wrap naturally; every
/// segment reserves the ruby line so baselines stay aligned across a line.
struct FuriganaText: View {
    let segments: [ReadingSegment]
    var baseSize: CGFloat = 34
    var weight: Font.Weight = .bold
    var alignment: HorizontalAlignment = .leading
    var baseColor: Color = .primary
    var rubyColor: Color = .secondary

    private var rubySize: CGFloat { baseSize * 0.42 }

    private var pieces: [ReadingSegment] {
        segments.flatMap { segment -> [ReadingSegment] in
            if segment.reading != nil { return [segment] }
            return segment.text.map { ReadingSegment(t: String($0), r: nil) }
        }
    }

    var body: some View {
        FlowLayout(alignment: alignment, lineSpacing: 6) {
            ForEach(Array(pieces.enumerated()), id: \.offset) { _, piece in
                VStack(spacing: 0) {
                    Text(piece.reading ?? "")
                        .font(.system(size: rubySize, weight: .medium))
                        .foregroundStyle(rubyColor)
                        .frame(height: rubySize * 1.4)
                        .lineLimit(1)
                        .fixedSize()
                    Text(piece.text)
                        .font(.system(size: baseSize, weight: weight))
                        .foregroundStyle(baseColor)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
    }
}

/// Minimal wrapping layout: places subviews left to right, breaking lines
/// when the proposed width is exhausted.
struct FlowLayout: Layout {
    var alignment: HorizontalAlignment = .leading
    var spacing: CGFloat = 0
    var lineSpacing: CGFloat = 0

    private struct Line {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let lines = arrange(subviews, maxWidth: maxWidth)
        let height = lines.reduce(0) { $0 + $1.height } + CGFloat(max(0, lines.count - 1)) * lineSpacing
        let widest = lines.map(\.width).max() ?? 0
        return CGSize(width: maxWidth == .infinity ? widest : min(maxWidth, max(widest, 0)), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let lines = arrange(subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for line in lines {
            var x = bounds.minX
            if alignment == .center {
                x = bounds.minX + (bounds.width - line.width) / 2
            } else if alignment == .trailing {
                x = bounds.maxX - line.width
            }
            for index in line.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + line.height - size.height),
                    anchor: .topLeading,
                    proposal: .unspecified
                )
                x += size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }

    private func arrange(_ subviews: Subviews, maxWidth: CGFloat) -> [Line] {
        var lines: [Line] = [Line()]
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            var current = lines[lines.count - 1]
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > maxWidth, !current.indices.isEmpty {
                lines.append(Line())
                current = lines[lines.count - 1]
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
            lines[lines.count - 1] = current
        }
        return lines
    }
}
