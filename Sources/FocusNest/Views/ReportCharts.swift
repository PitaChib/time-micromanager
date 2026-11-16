import SwiftUI
import Charts
import FocusCore

struct DailyTimeChart: View {
    let report: TimeReport
    let weekly: Bool
    let now: Date

    private var activeCategories: [ReportCategory] { report.categories.filter { $0.seconds > 0 } }
    private var maximum: Double { max(1, (report.days.map(\.seconds).max() ?? 0) / 3600 * 1.2) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(weekly ? "Your week, day by day" : "Daily hours").font(.title3.bold())
                Spacer()
                Text(weekly ? "Monday–Sunday · hours" : "Up to 31 days · hours")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if report.days.isEmpty {
                Text("No days to show yet.").foregroundStyle(.secondary).frame(height: 190)
            } else {
                Chart {
                    ForEach(report.days) { day in
                        ForEach(activeCategories) { category in
                            BarMark(x: .value("Day", day.date, unit: .day),
                                    y: .value("Hours", (day.secondsByCategory[category.id] ?? 0) / 3600),
                                    stacking: .standard)
                                .foregroundStyle(by: .value("Category", category.id.uuidString))
                                .accessibilityLabel("\(day.date.formatted(.dateTime.weekday(.wide))), \(category.name)")
                                .accessibilityValue("\(reportHours(day.secondsByCategory[category.id] ?? 0)) hours")
                        }
                        // A separate invisible mark labels the complete stack once.
                        PointMark(x: .value("Day", day.date, unit: .day), y: .value("Hours", day.seconds / 3600))
                            .opacity(0)
                            .annotation(position: .top) {
                                if report.days.count <= 7 && day.seconds > 0 {
                                    Text(reportHours(day.seconds)).font(.caption.bold()).monospacedDigit()
                                }
                            }
                    }
                }
                .chartForegroundStyleScale(domain: activeCategories.map { $0.id.uuidString },
                                           range: activeCategories.map { NestStyle.color($0.color) })
                .chartLegend(.hidden)
                .chartYScale(domain: 0...maximum)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: report.days.count <= 7 ? 1 : 5)) { _ in
                        AxisValueLabel(format: weekly ? .dateTime.weekday(.abbreviated) : .dateTime.month(.abbreviated).day())
                    }
                }
                .frame(height: 210)
                if weekly {
                    HStack(spacing: 8) {
                        ForEach(report.days) { day in
                            VStack(spacing: 5) {
                                Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(day.date > now ? "—" : "\(reportHours(day.seconds)) h")
                                    .font(.callout.bold()).monospacedDigit()
                            }.frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                        }
                    }
                }
                if !activeCategories.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading, spacing: 8) {
                        ForEach(activeCategories) { category in
                            HStack(spacing: 6) {
                                Circle().fill(NestStyle.color(category.color)).frame(width: 8, height: 8)
                                Text(category.name).font(.caption).lineLimit(1).help(category.name)
                            }
                        }
                    }
                }
            }
        }.reportCard()
    }
}

struct TimeDistributionChart: View {
    let report: TimeReport
    let weekly: Bool
    private var categories: [ReportCategory] { report.categories.filter { $0.seconds > 0 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(weekly ? "This week’s time split" : "Time split").font(.title3.bold())
            if report.seconds > 0 {
                Chart(categories) { category in
                    SectorMark(angle: .value("Hours", category.seconds / 3600), innerRadius: .ratio(0.70), angularInset: 2)
                        .foregroundStyle(by: .value("Category", category.id.uuidString))
                        .cornerRadius(3)
                        .accessibilityLabel(category.name)
                        .accessibilityValue("\(reportHours(category.seconds)) hours, \(percent(category.seconds)) percent")
                }
                .chartForegroundStyleScale(domain: categories.map { $0.id.uuidString },
                                           range: categories.map { NestStyle.color($0.color) })
                .chartLegend(.hidden)
                .frame(height: 200)
                .overlay {
                    VStack(spacing: 3) {
                        Text("\(reportHours(report.seconds)) h").font(.title2.bold()).monospacedDigit()
                        Text("Total hours").font(.caption).foregroundStyle(.secondary)
                    }.allowsHitTesting(false)
                }
                ForEach(categories) { category in
                    HStack(spacing: 8) {
                        Circle().fill(NestStyle.color(category.color)).frame(width: 8, height: 8)
                        Text(category.name).lineLimit(1).help(category.name)
                        Spacer(minLength: 8)
                        Text("\(percent(category.seconds))% · \(reportHours(category.seconds)) h")
                            .foregroundStyle(.secondary).monospacedDigit()
                    }.font(.caption)
                }
            } else {
                ContentUnavailableView("No time recorded", systemImage: "chart.pie", description: Text("Your time split will appear as you work."))
                    .frame(height: 200)
            }
        }.reportCard()
    }
    private func percent(_ seconds: Double) -> Int { Int((seconds / report.seconds * 100).rounded()) }
}

struct ProjectRankingChart: View {
    let report: TimeReport
    let weekly: Bool
    private var categories: [ReportCategory] {
        report.categories.sorted { $0.seconds > $1.seconds }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(weekly ? "Hours by category this week" : "Hours by category").font(.title3.bold())
                Spacer()
            }
            if categories.isEmpty {
                Text("Create a project to start tracking.").foregroundStyle(.secondary)
            } else {
                Chart(categories) { category in
                    BarMark(x: .value("Hours", category.seconds / 3600), y: .value("Category", category.id.uuidString))
                        .foregroundStyle(NestStyle.color(category.color))
                        .cornerRadius(4)
                        .annotation(position: .trailing) {
                            Text("\(reportHours(category.seconds)) h").font(.caption).monospacedDigit()
                        }
                        .accessibilityLabel(category.name)
                        .accessibilityValue("\(reportHours(category.seconds)) hours")
                }
                .chartYScale(domain: categories.map { $0.id.uuidString })
                .chartXScale(domain: 0...max(1, (categories.first?.seconds ?? 0) / 3600 * 1.35))
                .chartYAxis {
                    AxisMarks(values: categories.map { $0.id.uuidString }) { value in
                        AxisValueLabel {
                            if let id = value.as(String.self), let category = categories.first(where: { $0.id.uuidString == id }) {
                                Text(category.name).lineLimit(1).help(category.name).frame(maxWidth: 120, alignment: .trailing)
                            }
                        }
                    }
                }
                .frame(height: CGFloat(max(160, categories.count * 34)))
                Divider()
                HStack {
                    Text(weekly ? "Weekly total" : "Total hours").font(.headline)
                    Spacer()
                    Text("\(reportHours(report.seconds)) h").font(.title3.bold()).monospacedDigit()
                }
                Text("Subproject hours roll up to their parent. Each minute counts once.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.reportCard()
    }
}

private func reportHours(_ seconds: Double) -> String {
    (seconds / 3600).formatted(.number.precision(.fractionLength(1)))
}

private extension View {
    func reportCard() -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading).padding(22)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 18))
    }
}
