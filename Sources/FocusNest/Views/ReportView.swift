import SwiftUI
import FocusCore

struct ReportView: View {
    @ObservedObject var store: TrackerStore
    let range: DateInterval
    let filterID: UUID?
    let period: ReportPeriod
    private enum DetailPanel: String, CaseIterable, Identifiable {
        case projects = "Projects", charts = "Charts", notes = "Notes", goals = "Goals"
        var id: Self { self }
    }
    @State private var detailPanel: DetailPanel = .projects
    private var total: Double { store.total(in: range, projectID: filterID) }
    private var previousRange: DateInterval {
        let c = TimeMath.calendar
        if period == .week {
            return TimeMath.week(containing: c.date(byAdding: .day, value: -7, to: range.start)!)
        }
        if period == .month {
            return c.dateInterval(of: .month, for: c.date(byAdding: .month, value: -1, to: range.start)!)!
        }
        let count = max(1, c.dateComponents([.day], from: range.start, to: range.end).day ?? 1)
        return DateInterval(start: c.date(byAdding: .day, value: -count, to: range.start)!, end: range.start)
    }
    private var comparison: String {
        let previous = store.total(in: previousRange, projectID: filterID)
        let difference = (total - previous) / 3600
        return "\(difference >= 0 ? "+" : "")\(difference.formatted(.number.precision(.fractionLength(1)))) h"
    }
    var body: some View {
        let report = TimeReport(entries: store.book.entries, projects: store.book.projects,
                                range: range, projectID: filterID, now: store.now)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                metric(period == .week ? "WEEKLY TOTAL" : "TOTAL HOURS", value: "\(hours(total)) h",
                       subtitle: filterID == nil ? "Across all projects" : "Including subprojects", icon: "hourglass")
                if period != .all {
                    metric("\(period == .week ? "WEEKLY" : "PERIOD") CHANGE", value: comparison,
                           subtitle: period == .week ? "Compared with previous week" : "Compared with previous period", icon: "chart.line.uptrend.xyaxis")
                }
                metric("DAILY AVERAGE", value: "\(hours(average)) h", subtitle: "Per elapsed calendar day", icon: "sun.max")
            }
            if period == .week && filterID == nil {
                WeekTimelineView(report: report,
                                 segments: WeekSchedule.segments(entries: store.book.entries, projects: store.book.projects,
                                                                range: range, now: store.now), now: store.now)
            } else {
                DailyTimeChart(report: report, weekly: period == .week, now: store.now)
            }
            Picker("Dashboard details", selection: $detailPanel) {
                ForEach(DetailPanel.allCases.filter { filterID == nil || $0 != .notes }) { panel in
                    Text(panel.rawValue).tag(panel)
                }
            }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 420)
                .accessibilityIdentifier("dashboardDetailPicker")
            switch detailPanel {
            case .projects:
                projectDetails(report)
            case .charts:
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        TimeDistributionChart(report: report, weekly: period == .week).frame(minWidth: 280)
                        ProjectRankingChart(report: report, weekly: period == .week).frame(minWidth: 330)
                    }
                    VStack(spacing: 12) {
                        TimeDistributionChart(report: report, weekly: period == .week)
                        ProjectRankingChart(report: report, weekly: period == .week)
                    }
                }
            case .notes:
                NoteCloudPanel(words: NoteCloud.words(entries: store.book.entries, projects: store.book.projects,
                                                     range: range, now: store.now))
            case .goals:
                weeklyGoals.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
            }
        }.onChange(of: filterID) { _, id in
            if id != nil && detailPanel == .notes { detailPanel = .projects }
        }
    }
    private func projectDetails(_ report: TimeReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Time by project").font(.headline)
            Text("Hours recorded directly on each project, including subprojects.")
                .font(.caption).foregroundStyle(.secondary)
            if report.projectDetails.isEmpty {
                Text("No project time in this date range.").foregroundStyle(.secondary)
            }
            ForEach(report.projectDetails.sorted { store.path($0.id).localizedStandardCompare(store.path($1.id)) == .orderedAscending }) { project in
                HStack(spacing: 10) {
                    Circle().fill(NestStyle.color(project.color)).frame(width: 8, height: 8)
                    Text(store.path(project.id)).font(.callout)
                    Spacer()
                    Text("\(hours(project.seconds)) h").monospacedDigit()
                }
            }
            Divider()
            HStack {
                Text(period == .week ? "Weekly total" : "Total hours").font(.headline)
                Spacer()
                Text("\(hours(report.seconds)) h").font(.headline).monospacedDigit()
            }
            Text("The charts above group subprojects under their parent category. These rows show each project separately.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityIdentifier("overallProjectDetails")
    }
    private var average: Double {
        let end = min(range.end, store.now)
        guard end > range.start else { return 0 }
        let c = TimeMath.calendar
        let count = max(1, (c.dateComponents([.day], from: c.startOfDay(for: range.start), to: c.startOfDay(for: end.addingTimeInterval(-0.001))).day ?? 0) + 1)
        return total / Double(count)
    }
    private func hours(_ seconds: Double) -> String { (seconds / 3600).formatted(.number.precision(.fractionLength(1))) }
    private func metric(_ title: String, value: String, subtitle: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon).font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.85)
            Text(value).font(.system(size: 26, weight: .medium, design: .rounded)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            .help(subtitle)
    }
    private var weeklyGoals: some View {
        let week = period == .week ? range : TimeMath.week(containing: store.now)
        let ids = filterID.map { TimeMath.descendants(of: $0, projects: store.book.projects) }
        let projects = store.orderedProjects.filter { $0.weeklyGoal > 0 && (ids == nil || ids!.contains($0.id)) }
        return VStack(alignment: .leading, spacing: 18) {
            Text(period == .week ? "Weekly intentions" : "This week’s intentions")
                .font(.system(.title3, design: .rounded, weight: .semibold))
            if projects.isEmpty {
                Text("Give your week a gentle target. Edit a project to set a weekly goal in hours.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(projects) { p in
                let actual = store.total(in: week, projectID: p.id) / 3600
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(p.name).lineLimit(1)
                        Spacer()
                        Text("\(actual.formatted(.number.precision(.fractionLength(1)))) / \(p.weeklyGoal.formatted()) h")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    ProgressView(value: min(1, actual / p.weeklyGoal)).tint(NestStyle.color(p.color))
                    Text(actual >= p.weeklyGoal ? "Goal reached. Nicely done." : "\(Int(actual / p.weeklyGoal * 100))% of your weekly goal")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
