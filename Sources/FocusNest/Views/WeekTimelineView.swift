import SwiftUI
import FocusCore

struct WeekTimelineView: View {
    let report: TimeReport
    let segments: [TimelineSegment]
    let now: Date
    private let rulerWidth: CGFloat = 60
    private var axis: TimelineAxis { TimelineAxis(segments: segments) }
    private var dayHeight: CGFloat { CGFloat((axis.endMinute - axis.startMinute) / 60) * 18 }
    private func y(_ minute: Double) -> CGFloat { CGFloat((minute - axis.startMinute) / 60) * 18 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Your week, day by day").font(.headline)
                Spacer()
                Text("Local time").font(.caption).foregroundStyle(.secondary)
                Image(systemName: "info.circle").foregroundStyle(.secondary)
                    .help("Normally 5:30 AM–10 PM; expands to include earlier or later work. Hover over blocks for exact times.")
            }
            HStack(spacing: 0) {
                Color.clear.frame(width: rulerWidth, height: 1)
                ForEach(report.days) { day in
                    VStack(spacing: 3) {
                        Text(day.date.formatted(.dateTime.weekday(.abbreviated).day())).font(.caption).foregroundStyle(.secondary)
                        Text(day.date > now ? "—" : "\(hours(day.seconds)) h")
                            .font(.callout.bold()).monospacedDigit()
                    }.frame(maxWidth: .infinity).padding(.vertical, 6)
                        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal, 3)
                }
            }
            HStack(alignment: .top, spacing: 0) {
                timeRuler
                HStack(spacing: 0) {
                    ForEach(report.days) { day in
                        dayColumn(day.date)
                    }
                }.frame(height: dayHeight)
                    .background(.primary.opacity(0.015))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.08)) }
            }.padding(.vertical, 6)
            if !report.projectDetails.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading, spacing: 8) {
                    ForEach(report.projectDetails) { project in
                        HStack(spacing: 6) {
                            Circle().fill(NestStyle.color(project.color)).frame(width: 8, height: 8)
                            Text(project.name).font(.caption).lineLimit(1).help(project.name)
                        }
                    }
                }
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityIdentifier("weeklyTimeOfDay")
    }

    private var timeRuler: some View {
        ZStack(alignment: .topTrailing) {
            ForEach(axis.labelMinutes, id: \.self) { minute in
                Text(timeLabel(minute)).font(.system(size: 10)).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .offset(y: y(minute) - 6)
            }
        }.frame(width: rulerWidth - 8, height: dayHeight, alignment: .topTrailing).padding(.trailing, 8)
    }

    private func dayColumn(_ date: Date) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(axis.gridMinutes, id: \.self) { minute in
                    Rectangle().fill(.primary.opacity(axis.labelMinutes.contains(minute) ? 0.12 : 0.045))
                        .frame(height: 0.5).offset(y: y(minute))
                }
                Rectangle().fill(.primary.opacity(0.08)).frame(width: 0.5)
                ForEach(segments.filter { $0.day == date }) { segment in
                    block(segment, width: max(1, geometry.size.width - 6))
                        .offset(x: 3, y: y(segment.startMinute))
                }
            }
        }.frame(height: dayHeight)
    }

    private func block(_ segment: TimelineSegment, width: CGFloat) -> some View {
        let height = max(1, CGFloat((segment.endMinute - segment.startMinute) / 60) * 18)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 3).fill(NestStyle.color(segment.color).opacity(0.22))
            RoundedRectangle(cornerRadius: 3).strokeBorder(NestStyle.color(segment.color).opacity(0.65), lineWidth: 1)
            if height >= 14 {
                VStack(alignment: .leading, spacing: 2) {
                    Text(segment.projectName).font(.system(size: 9, weight: .semibold)).lineLimit(1)
                    if height >= 40 {
                        Text(segment.start.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }.padding(2)
            }
        }.frame(width: width, height: height).clipped()
            .help(description(segment))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(segment.projectName)
            .accessibilityValue(description(segment))
    }

    private func description(_ segment: TimelineSegment) -> String {
        "\(segment.projectName) · \(segment.start.formatted(date: .abbreviated, time: .shortened)) – \(segment.end.formatted(date: .abbreviated, time: .shortened)) · \(TimeMath.duration(segment.end.timeIntervalSince(segment.start)))"
    }
    private func hours(_ seconds: Double) -> String {
        (seconds / 3600).formatted(.number.precision(.fractionLength(1)))
    }
    private func timeLabel(_ minute: Double) -> String {
        let value = Int(minute)
        let hour = value / 60 % 24
        let minutes = value % 60
        let suffix = hour < 12 ? "AM" : "PM"
        let clockHour = hour % 12 == 0 ? 12 : hour % 12
        return minutes == 0 ? "\(clockHour) \(suffix)" : "\(clockHour):\(String(format: "%02d", minutes)) \(suffix)"
    }
}
