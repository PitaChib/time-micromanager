import SwiftUI
import FocusCore

struct NoteCloudPanel: View {
    let words: [NoteWord]

    private var categories: [NoteWord] {
        var seen: Set<UUID> = []
        return words.filter { seen.insert($0.categoryID).inserted }
            .sorted { $0.categoryName.localizedStandardCompare($1.categoryName) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("In your own words", systemImage: "text.bubble").font(.title3.bold())
            Text("Themes from your time-entry notes in this date range.")
                .font(.callout).foregroundStyle(.secondary)
            if words.isEmpty {
                ContentUnavailableView("A few words about your work", systemImage: "text.alignleft",
                                       description: Text("Add notes when recording or editing time. Your themes will appear here."))
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            } else {
                WordCloudLayout {
                    ForEach(words) { word in
                        Text(word.word)
                            .font(.system(size: fontSize(word), weight: word.mentions > 1 ? .semibold : .medium, design: .rounded))
                            .foregroundStyle(NestStyle.color(word.color))
                            .lineLimit(1).minimumScaleFactor(0.35)
                            .help("\(word.categoryName) · \(word.mentions) \(word.mentions == 1 ? "note" : "notes") mention this word")
                            .accessibilityLabel("\(word.word), \(word.mentions) notes, \(word.categoryName)")
                    }
                }.frame(maxWidth: .infinity).padding(.vertical, 12)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 8) {
                    ForEach(categories, id: \.categoryID) { category in
                        HStack(spacing: 6) {
                            Circle().fill(NestStyle.color(category.color)).frame(width: 8, height: 8)
                            Text(category.categoryName).font(.caption).lineLimit(1)
                        }
                    }
                }
                Text("Larger words appear in more notes. Color follows the top-level category mentioning the word most. Common words are omitted.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 18))
            .accessibilityIdentifier("notesWordCloud")
    }

    private func fontSize(_ word: NoteWord) -> CGFloat {
        let low = Double(words.last?.mentions ?? 1)
        let high = Double(words.first?.mentions ?? 1)
        guard high > low else { return 26 }
        return 16 + 26 * CGFloat((sqrt(Double(word.mentions)) - sqrt(low)) / (sqrt(high) - sqrt(low)))
    }
}

// Centered wrapping rows keep words readable without overlapping at small window sizes.
private struct WordCloudLayout: Layout {
    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }
    private let gap: CGFloat = 14

    private func rows(width: CGFloat, subviews: Subviews) -> [Row] {
        var result: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            if !row.indices.isEmpty && row.width + gap + size.width > width {
                result.append(row)
                row = Row()
            }
            row.width += (row.indices.isEmpty ? 0 : gap) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { result.append(row) }
        return result
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = max(1, proposal.width ?? 600)
        let rows = rows(width: width, subviews: subviews)
        return CGSize(width: width, height: rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * gap)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = bounds.midX - row.width / 2
            for index in row.indices {
                let size = subviews[index].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                      proposal: ProposedViewSize(size))
                x += size.width + gap
            }
            y += row.height + gap
        }
    }
}
