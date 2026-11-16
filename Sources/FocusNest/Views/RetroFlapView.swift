import SwiftUI

struct RetroFlapView: View {
    let value: String
    let caption: String
    let compact: Bool

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(LinearGradient(colors: [Color(red: 1, green: 0.52, blue: 0.24),
                                                   Color(red: 1, green: 0.66, blue: 0.30),
                                                   Color(red: 1, green: 0.48, blue: 0.17)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .orange.opacity(0.28), radius: 4)
                RoundedRectangle(cornerRadius: 6)
                    .fill(RadialGradient(colors: [Color(red: 1, green: 0.87, blue: 0.52).opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: 55))
                RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.28), lineWidth: 0.7)
                HStack(spacing: compact ? 2 : 3) {
                    ForEach(Array(value.enumerated()), id: \.offset) { _, digit in
                        SevenSegmentDigit(digit: digit)
                            .frame(width: compact ? 16 : 22, height: compact ? 32 : 40)
                    }
                }.padding(.horizontal, 4)
                Rectangle().fill(.black.opacity(0.16)).frame(height: 0.5)
                    .offset(y: 0.5)
                Ellipse().fill(Color(red: 1, green: 0.91, blue: 0.55).opacity(0.85))
                    .frame(width: 34, height: 6).blur(radius: 5).offset(y: -23)
            }.frame(height: 54)
            Text(caption).font(.system(size: 6, weight: .bold, design: .rounded)).tracking(1)
                .foregroundStyle(Color(red: 0.39, green: 0.30, blue: 0.23))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(caption == "HR" ? "hours" : caption == "MIN" ? "minutes" : "seconds")")
    }
}

private struct SevenSegmentDigit: View {
    let digit: Character
    private let shapes: [[CGPoint]] = [
        [CGPoint(x: 3, y: 0), CGPoint(x: 17, y: 0), CGPoint(x: 20, y: 2), CGPoint(x: 16, y: 5), CGPoint(x: 5, y: 5), CGPoint(x: 1, y: 2)],
        [CGPoint(x: 20, y: 3), CGPoint(x: 20, y: 15), CGPoint(x: 18, y: 18), CGPoint(x: 15, y: 15), CGPoint(x: 15, y: 7)],
        [CGPoint(x: 18, y: 20), CGPoint(x: 20, y: 23), CGPoint(x: 20, y: 35), CGPoint(x: 15, y: 31), CGPoint(x: 15, y: 23)],
        [CGPoint(x: 5, y: 33), CGPoint(x: 16, y: 33), CGPoint(x: 20, y: 37), CGPoint(x: 17, y: 38), CGPoint(x: 3, y: 38), CGPoint(x: 0, y: 36)],
        [CGPoint(x: 2, y: 20), CGPoint(x: 5, y: 23), CGPoint(x: 5, y: 31), CGPoint(x: 0, y: 35), CGPoint(x: 0, y: 23)],
        [CGPoint(x: 0, y: 3), CGPoint(x: 5, y: 7), CGPoint(x: 5, y: 15), CGPoint(x: 2, y: 18), CGPoint(x: 0, y: 15)],
        [CGPoint(x: 5, y: 17), CGPoint(x: 15, y: 17), CGPoint(x: 18, y: 19), CGPoint(x: 15, y: 21), CGPoint(x: 5, y: 21), CGPoint(x: 2, y: 19)]
    ]
    private var lit: Set<Int> {
        switch digit {
        case "0": return [0, 1, 2, 3, 4, 5]
        case "1": return [1, 2]
        case "2": return [0, 1, 6, 4, 3]
        case "3": return [0, 1, 6, 2, 3]
        case "4": return [5, 6, 1, 2]
        case "5": return [0, 5, 6, 2, 3]
        case "6": return [0, 5, 6, 4, 2, 3]
        case "7": return [0, 1, 2]
        case "8": return [0, 1, 2, 3, 4, 5, 6]
        case "9": return [0, 1, 2, 3, 5, 6]
        default: return []
        }
    }
    var body: some View {
        Canvas { context, size in
            for (index, points) in shapes.enumerated() {
                var path = Path()
                path.addLines(points.map { CGPoint(x: $0.x / 20 * size.width, y: $0.y / 38 * size.height) })
                path.closeSubpath()
                context.fill(path, with: .color(Color(red: 0.24, green: 0.16, blue: 0.13).opacity(lit.contains(index) ? 0.95 : 0.035)))
            }
        }
    }
}
