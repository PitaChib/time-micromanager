import Foundation
import FocusCore

struct FocusCoreChecks {
    let origin = Date(timeIntervalSince1970: 1_700_000_000)
    func notebook() -> Notebook {
        var n = Notebook()
        n.projects = [Project(name: "Research"), Project(name: "Teaching")]
        return n
    }
    func overallReportExposesHomeworkSeparatelyFromParentRollup() throws {
        let other = Project(name: "Other", color: 2)
        let homework = Project(name: "Class/Homework", parentID: other.id, color: 3)
        let child = Project(name: "Assignment", parentID: homework.id, color: 4)
        let research = Project(name: "Research", color: 5)
        let entries = [
            Entry(projectID: other.id, start: origin, end: origin.addingTimeInterval(1800)),
            Entry(projectID: homework.id, start: origin, end: origin.addingTimeInterval(5000)),
            Entry(projectID: child.id, start: origin, end: origin.addingTimeInterval(600)),
            Entry(projectID: research.id, start: origin, end: origin.addingTimeInterval(3600))
        ]
        let range = DateInterval(start: origin, duration: 7200)
        let report = TimeReport(entries: entries, projects: [other, homework, child, research], range: range, now: range.end)
        try expect(report.categories.first { $0.id == other.id }?.seconds == 7400)
        let detail = report.projectDetails.first { $0.id == homework.id }
        try expect(detail?.name == "Class/Homework" && detail?.seconds == 5000 && detail?.color == 3,
                   "All projects must expose homework hours separately from Other")
        try expect(report.projectDetails.reduce(0) { $0 + $1.seconds } == report.seconds,
                   "Detailed rows must sum to the overall total without counting child rollups twice")
        let selected = TimeReport(entries: entries, projects: [other, homework, child, research], range: range,
                                  projectID: homework.id, now: range.end)
        try expect(Set(selected.projectDetails.map(\.id)) == [homework.id, child.id])
        try expect(selected.projectDetails.reduce(0) { $0 + $1.seconds } == 5600)
    }
    func describeChunkPreservesOtherSessionsAndTime() throws {
        var n = notebook()
        let focus = UUID()
        let first = Entry(projectID: n.projects[0].id, focusID: focus, start: origin, end: origin.addingTimeInterval(120))
        let resumed = Entry(projectID: n.projects[0].id, focusID: focus, start: origin.addingTimeInterval(180), end: origin.addingTimeInterval(300))
        let earlier = Entry(projectID: n.projects[0].id, start: origin.addingTimeInterval(-3600), end: origin.addingTimeInterval(-1800), note: "Earlier work")
        n.entries = [earlier, first, resumed]
        try expect(n.describeTimeChunk(focusID: focus, note: "  Data analysis  \n"))
        try expect(n.entries[0] == earlier)
        for (before, after) in zip([first, resumed], n.entries.dropFirst()) {
            try expect(after.note == "Data analysis" && before.start == after.start && before.end == after.end)
            try expect(before.id == after.id && before.focusID == after.focusID && before.projectID == after.projectID)
        }
        let restored = try JSONDecoder().decode(Notebook.self, from: JSONEncoder().encode(n))
        try expect(restored == n, "The saved chunk description must persist with its time")
        let words = NoteCloud.words(entries: restored.entries, projects: restored.projects,
                                   range: DateInterval(start: origin, duration: 3600), now: origin.addingTimeInterval(3600))
        try expect(Set(words.map(\.word)) == ["data", "analysis"])
        try expect(words.allSatisfy { $0.mentions == 1 && $0.categoryID == n.projects[0].id },
                   "Paused/resumed portions of one saved chunk should contribute one theme mention")
    }
    func describeChunkRejectsBlankUnknownAndRunningTargets() throws {
        var n = notebook()
        n.start(projectID: n.projects[0].id, at: origin)
        let focus = n.activeEntry!.focusID
        let running = n
        try expect(!n.describeTimeChunk(focusID: focus, note: "analysis") && n == running)
        n.stop(at: origin.addingTimeInterval(60))
        let paused = n
        try expect(!n.describeTimeChunk(focusID: focus, note: "  \n") && n == paused)
        try expect(!n.describeTimeChunk(focusID: UUID(), note: "analysis") && n == paused)
    }
    func describeChunkCannotBypassAwayReview() throws {
        var n = notebook()
        n.start(projectID: n.projects[0].id, at: origin)
        let focus = n.activeEntry!.focusID
        n.pauseForReview(at: origin.addingTimeInterval(60), reason: "Idle")
        let pending = n
        try expect(!n.describeTimeChunk(focusID: focus, note: "analysis") && n == pending)
    }
    func timelineAxisDefaultsToFiveThirtyAndTenPM() throws {
        let empty = TimelineAxis(segments: [])
        try expect(empty.startMinute == 330 && empty.endMinute == 1320)
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = c.date(from: DateComponents(year: 2026, month: 10, day: 19))!
        let p = Project(name: "Research")
        let end = day.addingTimeInterval(22 * 3600)
        let pieces = WeekSchedule.segments(entries: [Entry(projectID: p.id, start: day.addingTimeInterval(5.5 * 3600), end: end)],
                                           projects: [p], range: DateInterval(start: day, duration: 86400), now: end, calendar: c)
        let axis = TimelineAxis(segments: pieces)
        try expect(axis.startMinute == 330 && axis.endMinute == 1320)
        try expect(axis.labelMinutes.first == 330 && axis.labelMinutes.last == 1320)
        try expect(zip(axis.labelMinutes, axis.labelMinutes.dropFirst()).allSatisfy { $1 - $0 >= 60 }, "Axis labels need readable spacing")
    }
    func timelineAxisExpandsForEarlyAndLateEntries() throws {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = c.date(from: DateComponents(year: 2026, month: 10, day: 19))!
        let p = Project(name: "Research")
        let end = day.addingTimeInterval((23 * 60 + 5) * 60)
        let entries = [Entry(projectID: p.id, start: day.addingTimeInterval((4 * 60 + 12) * 60), end: day.addingTimeInterval(5 * 3600)),
                       Entry(projectID: p.id, start: day.addingTimeInterval(21 * 3600))]
        let pieces = WeekSchedule.segments(entries: entries, projects: [p], range: DateInterval(start: day, duration: 86400), now: end, calendar: c)
        let axis = TimelineAxis(segments: pieces)
        try expect(axis.startMinute == 240 && axis.endMinute == 1410, "Bounds expand outward to include entered and running time")
        try expect(pieces.allSatisfy { $0.startMinute >= axis.startMinute && $0.endMinute <= axis.endMinute })
        try expect(axis.gridMinutes.first == 240 && axis.gridMinutes.last == 1410)
        let lateOnly = TimelineAxis(segments: Array(pieces.suffix(1)))
        try expect(lateOnly.startMinute == 330 && lateOnly.endMinute == 1410)
    }
    func timelineAxisIncludesBothSidesOfMidnight() throws {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = c.date(from: DateComponents(year: 2026, month: 10, day: 19))!
        let p = Project(name: "Writing")
        let start = day.addingTimeInterval((23 * 60 + 40) * 60)
        let end = day.addingTimeInterval((24 * 60 + 20) * 60)
        let pieces = WeekSchedule.segments(entries: [Entry(projectID: p.id, start: start, end: end)], projects: [p],
                                           range: DateInterval(start: day, duration: 2 * 86400), now: end, calendar: c)
        let axis = TimelineAxis(segments: pieces)
        try expect(pieces.count == 2 && axis.startMinute == 0 && axis.endMinute == 1440)
        try expect(pieces.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) } == 40 * 60)
        try expect(axis.labelMinutes == Array(Set(axis.labelMinutes)).sorted())
    }
    func timelineKeepsActualClockTimesAndTaskColors() throws {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        c.firstWeekday = 2; c.minimumDaysInFirstWeek = 4
        let day = c.date(from: DateComponents(year: 2026, month: 10, day: 19))!
        let p = Project(name: "Homework", color: 11)
        let start = day.addingTimeInterval((9 * 60 + 15) * 60)
        let finish = start.addingTimeInterval(90 * 60)
        let entry = Entry(projectID: p.id, start: start, end: finish)
        let pieces = WeekSchedule.segments(entries: [entry], projects: [p], range: TimeMath.week(containing: day, calendar: c),
                                           now: finish, calendar: c)
        try expect(pieces.count == 1)
        try expect(pieces[0].day == day && pieces[0].startMinute == 555 && pieces[0].endMinute == 645)
        try expect(pieces[0].projectID == p.id && pieces[0].projectName == "Homework" && pieces[0].color == 11)
        try expect(pieces[0].entryID == entry.id && pieces[0].start == start && pieces[0].end == finish)
    }
    func timelineSplitsMidnightClipsRangeAndReconcilesDailyTotals() throws {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        c.firstWeekday = 2; c.minimumDaysInFirstWeek = 4
        let monday = c.date(from: DateComponents(year: 2026, month: 10, day: 19))!
        let tuesday = c.date(byAdding: .day, value: 1, to: monday)!
        let p = Project(name: "Research")
        let now = tuesday.addingTimeInterval(8.75 * 3600)
        let entries = [
            Entry(projectID: p.id, start: monday.addingTimeInterval(-3600), end: monday.addingTimeInterval(1800)),
            Entry(projectID: p.id, start: monday.addingTimeInterval(23.5 * 3600), end: tuesday.addingTimeInterval(1.25 * 3600)),
            Entry(projectID: p.id, start: tuesday.addingTimeInterval(8 * 3600)),
            Entry(projectID: p.id, start: monday.addingTimeInterval(-7200), end: monday)
        ]
        let range = TimeMath.week(containing: monday, calendar: c)
        let pieces = WeekSchedule.segments(entries: entries, projects: [p], range: range, now: now, calendar: c)
        try expect(pieces.count == 4 && Set(pieces.map(\.id)).count == 4)
        try expect(pieces[1].startMinute == 1410 && pieces[1].endMinute == 1440)
        try expect(pieces[2].startMinute == 0 && pieces[2].endMinute == 75)
        try expect(pieces.last?.end == now && pieces.last?.endMinute == 525)
        let report = TimeReport(entries: entries, projects: [p], range: range, now: now, calendar: c)
        for day in report.days {
            let actual = pieces.filter { $0.day == day.date }.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
            try expect(actual == day.seconds, "Timeline chunks must match each retained daily hours label")
        }
        try expect(pieces.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) } == report.seconds)
    }
    func timelinePreservesHoursAcrossClockChanges() throws {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        let p = Project(name: "Reading")
        for (month, day, expectedHours, secondStart) in [(3, 8, 3.0, 180.0), (11, 1, 5.0, 60.0)] {
            let start = c.date(from: DateComponents(year: 2026, month: month, day: day))!
            let end = c.date(from: DateComponents(year: 2026, month: month, day: day, hour: 4))!
            let pieces = WeekSchedule.segments(entries: [Entry(projectID: p.id, start: start, end: end)], projects: [p],
                                               range: DateInterval(start: start, end: end), now: end, calendar: c)
            try expect(pieces.count == 2 && pieces[0].endMinute == 120 && pieces[1].startMinute == secondStart)
            try expect(pieces.allSatisfy { $0.startMinute >= 0 && $0.endMinute <= 1440 && $0.endMinute > $0.startMinute })
            try expect(pieces.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) } == expectedHours * 3600)
        }
    }
    func reportStacksDaysAndReconcilesWeeklyTotals() throws {
        let parent = Project(name: "Research", color: 0)
        let child = Project(name: "Paper", parentID: parent.id, color: 4)
        let teaching = Project(name: "Teaching", color: 1)
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        c.firstWeekday = 2; c.minimumDaysInFirstWeek = 4
        let monday = c.date(from: DateComponents(year: 2026, month: 10, day: 19))!
        let week = TimeMath.week(containing: monday, calendar: c)
        let late = c.date(byAdding: .hour, value: 23, to: monday)!
        let entries = [Entry(projectID: child.id, start: late, end: late.addingTimeInterval(7200)),
                       Entry(projectID: teaching.id, start: monday, end: monday.addingTimeInterval(10800))]
        let report = TimeReport(entries: entries, projects: [parent, child, teaching], range: week,
                                now: monday.addingTimeInterval(36 * 3600), calendar: c)
        try expect(report.days.count == 7, "Weekly reports include Monday through Sunday")
        try expect(report.days[0].seconds == 14400 && report.days[1].seconds == 3600)
        try expect(report.days.dropFirst(2).allSatisfy { $0.seconds == 0 })
        try expect(report.categories.first { $0.id == parent.id }?.seconds == 7200)
        try expect(report.seconds == 18000 && report.days.reduce(0) { $0 + $1.seconds } == report.seconds)
        try expect(report.seconds == TimeMath.seconds(entries, in: week), "Each recorded minute belongs to exactly one category")
    }
    func selectedReportSeparatesDirectTimeAndDescendants() throws {
        let parent = Project(name: "Research", color: 0)
        let child = Project(name: "Paper", parentID: parent.id, color: 7)
        let grandchild = Project(name: "Reading", parentID: child.id, color: 12)
        let other = Project(name: "Teaching")
        let entries = [parent, child, grandchild, other].map {
            Entry(projectID: $0.id, start: origin, end: origin.addingTimeInterval(3600))
        }
        let report = TimeReport(entries: entries, projects: [parent, child, grandchild, other],
                                range: DateInterval(start: origin.addingTimeInterval(1800), duration: 3600),
                                projectID: parent.id, now: origin.addingTimeInterval(7200))
        try expect(report.categories.count == 2)
        try expect(report.categories.first { $0.id == parent.id }?.seconds == 1800)
        try expect(report.categories.first { $0.id == child.id }?.seconds == 3600)
        try expect(report.categories.first { $0.id == child.id }?.color == 7)
        try expect(report.seconds == 5400 && report.days.reduce(0) { $0 + $1.seconds } == 5400)
    }
    func reportClipsLiveTimeAndHandlesDaylightSaving() throws {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        c.firstWeekday = 2; c.minimumDaysInFirstWeek = 4
        let sunday = c.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let monday = c.date(byAdding: .day, value: 1, to: sunday)!
        let p = Project(name: "Research")
        let entry = Entry(projectID: p.id, start: sunday)
        let week = TimeMath.week(containing: sunday, calendar: c)
        let report = TimeReport(entries: [entry], projects: [p], range: week, now: monday, calendar: c)
        try expect(report.days.count == 7 && report.days.last?.seconds == 25 * 3600)
        try expect(report.seconds == 25 * 3600)
        let live = TimeReport(entries: [entry], projects: [p], range: week,
                              now: sunday.addingTimeInterval(3600), calendar: c)
        try expect(live.seconds == 3600 && live.days.last?.seconds == 3600)
    }
    func longReportKeepsFullTotalsWhileLimitingDailyChart() throws {
        let p = Project(name: "Research")
        let end = TimeMath.calendar.date(byAdding: .day, value: 90, to: origin)!
        let entries = [Entry(projectID: p.id, start: origin, end: origin.addingTimeInterval(3600))]
        let report = TimeReport(entries: entries, projects: [p], range: DateInterval(start: origin, end: end), now: end)
        try expect(report.days.count <= 31)
        try expect(report.seconds == 3600, "Full-range totals must not be truncated with the daily chart")
    }
    func notesCloudFiltersRangeAndCountsNoteMentions() throws {
        let p = Project(name: "Research", color: 8)
        let range = DateInterval(start: origin, duration: 3600)
        let entries = [
            Entry(projectID: p.id, start: origin, end: origin.addingTimeInterval(60), note: "The analysis, ANALYSIS and figures."),
            Entry(projectID: p.id, start: origin.addingTimeInterval(60), end: origin.addingTimeInterval(120), note: "Analysis with models"),
            Entry(projectID: p.id, start: origin.addingTimeInterval(-60), end: origin, note: "Excluded before"),
            Entry(projectID: p.id, start: range.end, end: range.end.addingTimeInterval(60), note: "Excluded after"),
            Entry(projectID: p.id, start: origin, end: origin.addingTimeInterval(60), note: "  ")
        ]
        let words = NoteCloud.words(entries: entries, projects: [p], range: range, now: range.end)
        try expect(words.first?.word == "analysis" && words.first?.mentions == 2)
        try expect(Set(words.map(\.word)) == ["analysis", "figures", "models"])
        try expect(words.allSatisfy { $0.categoryID == p.id && $0.color == 8 })
    }
    func notesCloudUsesTopCategoryAndDominantColor() throws {
        let research = Project(name: "Research", color: 5)
        let paper = Project(name: "Paper", parentID: research.id, color: 11)
        let reading = Project(name: "Reading", parentID: paper.id, color: 12)
        let teaching = Project(name: "Teaching", color: 7)
        let entries = [
            Entry(projectID: paper.id, start: origin, end: origin.addingTimeInterval(60), note: "analysis"),
            Entry(projectID: reading.id, start: origin, end: origin.addingTimeInterval(60), note: "analysis"),
            Entry(projectID: teaching.id, start: origin, end: origin.addingTimeInterval(60), note: "analysis lectures")
        ]
        let projects = [research, paper, reading, teaching]
        let range = DateInterval(start: origin, duration: 3600)
        let words = NoteCloud.words(entries: entries, projects: projects, range: range, now: range.end)
        let analysis = words.first { $0.word == "analysis" }
        try expect(analysis?.mentions == 3 && analysis?.categoryID == research.id && analysis?.color == 5)
        try expect(words.first { $0.word == "lectures" }?.categoryID == teaching.id)
        let reversed = NoteCloud.words(entries: entries.reversed(), projects: projects, range: range, now: range.end)
        try expect(words.map(\.word) == reversed.map(\.word) && words.map(\.categoryID) == reversed.map(\.categoryID))
    }
    func notesCloudDoesNotDoubleCountSplitNotes() throws {
        let p = Project(name: "Research")
        let session = UUID()
        let range = DateInterval(start: origin, duration: 3600)
        let entries = [
            Entry(projectID: p.id, focusID: session, start: origin, end: origin.addingTimeInterval(60), note: "Reading papers"),
            Entry(projectID: p.id, focusID: session, start: origin.addingTimeInterval(120), end: origin.addingTimeInterval(180), note: "Reading papers"),
            Entry(projectID: p.id, start: origin.addingTimeInterval(200), end: origin.addingTimeInterval(240), note: "Reading papers")
        ]
        let words = NoteCloud.words(entries: entries, projects: [p], range: range, now: range.end)
        try expect(words.count == 2 && words.allSatisfy { $0.mentions == 2 })
        try expect(NoteCloud.words(entries: [], projects: [p], range: range, now: range.end).isEmpty)
        let common = Entry(projectID: p.id, start: origin, end: origin.addingTimeInterval(60), note: "the and with 123")
        try expect(NoteCloud.words(entries: [common], projects: [p], range: range, now: range.end).isEmpty)
    }
    func switchStopsPreviousTimer() throws {
        var n = notebook()
        n.start(projectID: n.projects[0].id, at: origin)
        n.start(projectID: n.projects[1].id, at: origin.addingTimeInterval(60))
        try expect(n.entries.filter { $0.end == nil }.count == 1)
        try expect(n.entries[0].end == origin.addingTimeInterval(60))
    }
    func idleCutsBackToLastInputAndReviewCanRestoreTime() throws {
        var n = notebook()
        n.start(projectID: n.projects[0].id, at: origin)
        let cutoff = origin.addingTimeInterval(100)
        n.pauseForReview(at: cutoff, reason: "Idle")
        try expect(n.activeEntry == nil)
        try expect(n.entries[0].end == cutoff)
        let returned = origin.addingTimeInterval(1000)
        n.start(projectID: n.projects[1].id, at: returned)
        try expect(n.activeEntry == nil, "Pending review must block another timer")
        n.resolveReview(countUntil: returned, resume: true, at: returned)
        try expect(n.entries[1].start == cutoff)
        try expect(n.entries[1].end == returned)
        try expect(n.activeEntry?.focusID == n.entries[0].focusID)
    }
    func crashRecoveryOnlyTrustsLastHeartbeat() throws {
        var n = notebook()
        n.start(projectID: n.projects[0].id, at: origin)
        n.heartbeat = origin.addingTimeInterval(30)
        let data = try JSONEncoder().encode(n)
        var recovered = try JSONDecoder().decode(Notebook.self, from: data)
        recovered.recoverAfterRelaunch()
        try expect(recovered.entries[0].end == n.heartbeat)
        try expect(recovered.review != nil)
    }
    func parentRollupAndIntervalClipping() throws {
        let parent = Project(name: "Research")
        let child = Project(name: "Paper", parentID: parent.id)
        let unrelated = Project(name: "Teaching")
        let entries = [Entry(projectID: child.id, start: origin, end: origin.addingTimeInterval(3600)),
                       Entry(projectID: unrelated.id, start: origin, end: origin.addingTimeInterval(3600))]
        let range = DateInterval(start: origin.addingTimeInterval(1800), duration: 3600)
        let ids = TimeMath.descendants(of: parent.id, projects: [parent, child, unrelated])
        try expect(TimeMath.seconds(entries, in: range, projectIDs: ids) == 1800)
    }
    func adjacentEntriesAllowedButOverlapsRejected() throws {
        let id = UUID()
        let first = Entry(projectID: id, start: origin, end: origin.addingTimeInterval(60))
        let adjacent = Entry(projectID: id, start: origin.addingTimeInterval(60), end: origin.addingTimeInterval(120))
        let overlap = Entry(projectID: id, start: origin.addingTimeInterval(59), end: origin.addingTimeInterval(120))
        try expect(!TimeMath.overlaps(adjacent, entries: [first]))
        try expect(TimeMath.overlaps(overlap, entries: [first]))
    }
    func daylightSavingWeekHasCalendarBoundaries() throws {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        c.firstWeekday = 2; c.minimumDaysInFirstWeek = 4
        let date = c.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12))!
        let week = TimeMath.week(containing: date, calendar: c)
        try expect(c.component(.weekday, from: week.start) == 2)
        try expect(week.duration == 169 * 3600)
    }
    func idleBeforeSessionDoesNotPauseNewTimer() throws {
        let cutoff = TimeMath.idleCutoff(sessionStart: origin, now: origin.addingTimeInterval(2), idleSeconds: 1500, threshold: 600)
        try expect(cutoff == nil, "Pre-session inactivity must not immediately pause a new timer")
        let later = TimeMath.idleCutoff(sessionStart: origin, now: origin.addingTimeInterval(601), idleSeconds: 2100, threshold: 600)
        try expect(later == origin, "A session started while idle should pause only after its own threshold")
        let input = TimeMath.idleCutoff(sessionStart: origin, now: origin.addingTimeInterval(1000), idleSeconds: 700, threshold: 600)
        try expect(input == origin.addingTimeInterval(300), "Pause must trim back to last input within the session")
    }
    func returnReviewUsesActualReturnTime() throws {
        var n = notebook()
        n.start(projectID: n.projects[0].id, at: origin)
        n.pauseForReview(at: origin.addingTimeInterval(60), reason: "Idle")
        try expect(n.review?.returnedAt == nil, "Review must wait until the user returns")
        let returned = origin.addingTimeInterval(7200)
        n.markReturned(at: returned)
        n.markReturned(at: returned.addingTimeInterval(60))
        try expect(n.review?.returnedAt == returned, "The first actual return anchors the review")
        n.resolveReview(countUntil: returned, resume: false, at: returned.addingTimeInterval(60))
        let total = TimeMath.seconds(n.entries, in: DateInterval(start: origin, duration: 8000))
        try expect(total == 7200, "A long reading session can retain all time until return")
    }
    func notebookSurvivesDiskRoundTrip() throws {
        var n = notebook()
        let paper = Project(name: "Paper", parentID: n.projects[0].id, weeklyGoal: 7.5, color: 3)
        n.projects.append(paper)
        n.idleMinutes = 20
        n.entries.append(Entry(projectID: paper.id, start: origin, end: origin.addingTimeInterval(3600), note: "Work recorded manually"))
        n.start(projectID: paper.id, at: origin.addingTimeInterval(4000))
        n.pauseForReview(at: origin.addingTimeInterval(4600), reason: "Sleep")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("FocusNest-check-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("notebook.json")
        try JSONEncoder().encode(n).write(to: file, options: .atomic)
        let loaded = try JSONDecoder().decode(Notebook.self, from: Data(contentsOf: file))
        try expect(loaded == n, "Projects, goals, notes, settings, entries and pending review must survive a disk save")
    }
    func overrideRequiresConfirmationAndCancelChangesNothing() throws {
        var n = notebook()
        let old = Entry(projectID: n.projects[0].id, start: origin, end: origin.addingTimeInterval(7200))
        let added = Entry(projectID: n.projects[1].id, start: origin.addingTimeInterval(3600), end: origin.addingTimeInterval(10800))
        n.entries = [old]
        let before = n
        try expect(n.saveEntry(added, now: origin.addingTimeInterval(12000)) == .conflicts([old]))
        try expect(n == before, "Warning and cancel must leave all records untouched")
    }
    func overrideTrimsOnlyOverlappingTime() throws {
        var n = notebook()
        let old = Entry(projectID: n.projects[0].id, start: origin, end: origin.addingTimeInterval(7200), note: "Keep my note")
        let added = Entry(projectID: n.projects[1].id, start: origin.addingTimeInterval(3600), end: origin.addingTimeInterval(10800))
        n.entries = [old]
        try expect(n.saveEntry(added, overrideOverlaps: true, now: origin.addingTimeInterval(12000)) == .saved)
        try expect(n.entries.count == 2)
        let retained = n.entries.first { $0.id == old.id }
        try expect(retained?.start == origin && retained?.end == added.start)
        try expect(retained?.note == old.note && retained?.focusID == old.focusID)
        try expect(n.entries.contains(added))
        try expect(!TimeMath.overlaps(added, entries: n.entries))
    }
    func overrideSplitsAnEntryAndPreservesBothSides() throws {
        var n = notebook()
        let old = Entry(projectID: n.projects[0].id, start: origin, end: origin.addingTimeInterval(10800), note: "Reading")
        let added = Entry(projectID: n.projects[1].id, start: origin.addingTimeInterval(3600), end: origin.addingTimeInterval(7200))
        n.entries = [old]
        _ = n.saveEntry(added, overrideOverlaps: true, now: origin.addingTimeInterval(12000))
        let parts = n.entries.filter { $0.projectID == old.projectID }.sorted { $0.start < $1.start }
        try expect(parts.count == 2)
        try expect(parts[0].start == old.start && parts[0].end == added.start)
        try expect(parts[1].start == added.end && parts[1].end == old.end)
        try expect(parts.allSatisfy { $0.note == old.note && $0.focusID == old.focusID })
        try expect(Set(n.entries.map(\.id)).count == 3, "Splits must have unique IDs")
        try expect(TimeMath.seconds(n.entries, in: DateInterval(start: origin, duration: 12000)) == 10800)
    }
    func overrideHandlesMultipleAndFullyCoveredEntries() throws {
        var n = notebook()
        let id = n.projects[0].id
        let first = Entry(projectID: id, start: origin, end: origin.addingTimeInterval(3600))
        let middle = Entry(projectID: id, start: origin.addingTimeInterval(3600), end: origin.addingTimeInterval(7200))
        let last = Entry(projectID: id, start: origin.addingTimeInterval(7200), end: origin.addingTimeInterval(10800))
        let adjacent = Entry(projectID: id, start: origin.addingTimeInterval(10800), end: origin.addingTimeInterval(12000))
        let added = Entry(projectID: n.projects[1].id, start: origin.addingTimeInterval(1800), end: origin.addingTimeInterval(9000))
        n.entries = [first, middle, last, adjacent]
        _ = n.saveEntry(added, overrideOverlaps: true, now: origin.addingTimeInterval(13000))
        try expect(!n.entries.contains { $0.id == middle.id })
        try expect(n.entries.first { $0.id == first.id }?.end == added.start)
        try expect(n.entries.first { $0.id == last.id }?.start == added.end)
        try expect(n.entries.contains(adjacent))
        try expect(TimeMath.seconds(n.entries, in: DateInterval(start: origin, duration: 13000)) == 12000)
    }
    func overridingAnEditDoesNotConflictWithItself() throws {
        var n = notebook()
        let old = Entry(projectID: n.projects[0].id, start: origin, end: origin.addingTimeInterval(3600))
        let other = Entry(projectID: n.projects[1].id, start: origin.addingTimeInterval(3600), end: origin.addingTimeInterval(7200))
        n.entries = [old, other]
        var edited = old
        edited.end = origin.addingTimeInterval(5400)
        try expect(n.saveEntry(edited, now: origin.addingTimeInterval(9000)) == .conflicts([other]))
        _ = n.saveEntry(edited, overrideOverlaps: true, now: origin.addingTimeInterval(9000))
        try expect(n.entries.filter { $0.id == old.id }.count == 1)
        try expect(n.entries.contains(edited))
        try expect(n.entries.first { $0.id == other.id }?.start == edited.end)
    }
    func overridePreservesRunningTimerAndValidatesBeforeMutation() throws {
        var n = notebook()
        n.start(projectID: n.projects[0].id, at: origin)
        let active = n.activeEntry!
        var added = Entry(projectID: n.projects[1].id, start: origin.addingTimeInterval(3600), end: origin.addingTimeInterval(7200))
        let now = origin.addingTimeInterval(10800)
        try expect(n.saveEntry(added, overrideOverlaps: true, now: now) == .saved)
        try expect(n.activeEntry?.start == added.end && n.activeEntry?.focusID == active.focusID)
        try expect(n.entries.filter { $0.end == nil }.count == 1)
        try expect(TimeMath.seconds(n.entries, in: DateInterval(start: origin, end: now), now: now) == 10800)
        let before = n
        added.end = now.addingTimeInterval(60)
        try expect(n.saveEntry(added, overrideOverlaps: true, now: now) == .invalid("Recorded time cannot end in the future."))
        try expect(n == before)
    }
    func idleSamplingIncludesInputFromEveryApp() throws {
        try expect(SystemActivity.inputEventType.rawValue == UInt32.max,
                   "The idle clock must sample any keyboard/mouse input, not null events")
    }
    func delayedBackgroundUpdateDoesNotPauseActiveWork() throws {
        var n = notebook()
        n.start(projectID: n.projects[0].id, at: origin)
        let later = origin.addingTimeInterval(3600)
        n.checkInactivity(at: later, idleSeconds: 1)
        try expect(n.activeEntry != nil && n.review == nil,
                   "A delayed update while working in another app must keep tracking")
        try expect(n.heartbeat == later)
        try expect(TimeMath.seconds(n.entries, in: DateInterval(start: origin, end: later), now: later) == 3600)
    }
    func actualComputerInactivityStillPausesAtLastInput() throws {
        var n = notebook()
        n.start(projectID: n.projects[0].id, at: origin)
        let later = origin.addingTimeInterval(1800)
        n.checkInactivity(at: later, idleSeconds: 900)
        try expect(n.activeEntry == nil)
        try expect(n.review?.start == origin.addingTimeInterval(900),
                   "True inactivity must trim to actual last input, not the last app update")
    }
    func discardPausedSessionKeepsProjectsAndOtherSessions() throws {
        var n = notebook()
        let projectID = n.projects[0].id
        let earlier = Entry(projectID: projectID, start: origin, end: origin.addingTimeInterval(60), note: "Keep earlier work")
        let otherProject = Entry(projectID: n.projects[1].id, start: origin.addingTimeInterval(60), end: origin.addingTimeInterval(120))
        n.entries = [earlier, otherProject]
        let focusID = UUID()
        n.start(projectID: projectID, focusID: focusID, at: origin.addingTimeInterval(200))
        n.stop(at: origin.addingTimeInterval(260))
        n.start(projectID: projectID, focusID: focusID, at: origin.addingTimeInterval(300))
        n.stop(at: origin.addingTimeInterval(420))
        let projects = n.projects
        try expect(n.discardPausedSession(focusID: focusID))
        try expect(n.entries == [earlier, otherProject], "Only this session’s paused/resumed parts should be removed")
        try expect(n.projects == projects, "Discard must never delete or alter projects")
        let reloaded = try JSONDecoder().decode(Notebook.self, from: JSONEncoder().encode(n))
        try expect(reloaded.entries == [earlier, otherProject], "Discarded time must stay removed after saving")
        try expect(!n.discardPausedSession(focusID: focusID), "A second confirmation must not remove any other session")
    }
    func discardCannotRemoveARunningSession() throws {
        var n = notebook()
        let focusID = UUID()
        n.start(projectID: n.projects[0].id, focusID: focusID, at: origin)
        let before = n
        try expect(!n.discardPausedSession(focusID: focusID))
        try expect(n == before, "Starting/resuming before confirmation must protect the running timer")
    }
    func discardCannotBypassReviewOrTargetUnknownSession() throws {
        var n = notebook()
        let focusID = UUID()
        n.start(projectID: n.projects[0].id, focusID: focusID, at: origin)
        n.pauseForReview(at: origin.addingTimeInterval(60), reason: "Idle")
        let before = n
        try expect(!n.discardPausedSession(focusID: focusID))
        try expect(n == before, "Pending away-time review must stay untouched")
        n.resolveReview(countUntil: nil, resume: false, at: origin.addingTimeInterval(120))
        let reviewed = n
        try expect(!n.discardPausedSession(focusID: UUID()))
        try expect(n == reviewed, "An unknown session must not delete records")
    }
}


struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String = "Check failed", file: StaticString = #filePath, line: UInt = #line) throws {
    if !condition() { throw CheckFailure(description: "\(file):\(line): \(message)") }
}

let checks = FocusCoreChecks()
let cases: [(String, () throws -> Void)] = [
    ("Saved chunk descriptions preserve time and feed themes once", checks.describeChunkPreservesOtherSessionsAndTime),
    ("Chunk descriptions reject blank, unknown, and running targets", checks.describeChunkRejectsBlankUnknownAndRunningTargets),
    ("Chunk saving cannot bypass away-time review", checks.describeChunkCannotBypassAwayReview),
    ("Timeline defaults to a compact 5:30 AM–10 PM axis", checks.timelineAxisDefaultsToFiveThirtyAndTenPM),
    ("Timeline automatically includes early and late work", checks.timelineAxisExpandsForEarlyAndLateEntries),
    ("Timeline expands through midnight without losing time", checks.timelineAxisIncludesBothSidesOfMidnight),
    ("Weekly timeline preserves actual clock times and task colors", checks.timelineKeepsActualClockTimesAndTaskColors),
    ("Timeline clips and splits sessions while matching daily totals", checks.timelineSplitsMidnightClipsRangeAndReconcilesDailyTotals),
    ("Timeline preserves elapsed hours across clock changes", checks.timelinePreservesHoursAcrossClockChanges),
    ("Overall report exposes homework and nested project hours without double counting", checks.overallReportExposesHomeworkSeparatelyFromParentRollup),
    ("Note cloud respects report dates and counts distinct note mentions", checks.notesCloudFiltersRangeAndCountsNoteMentions),
    ("Note cloud uses dominant top-level category colors", checks.notesCloudUsesTopCategoryAndDominantColor),
    ("Note cloud deduplicates split sessions and handles empty notes", checks.notesCloudDoesNotDoubleCountSplitNotes),
    ("Weekly daily stacks reconcile with category and total hours", checks.reportStacksDaysAndReconcilesWeeklyTotals),
    ("Selected category partitions direct and nested subproject time", checks.selectedReportSeparatesDirectTimeAndDescendants),
    ("Daily report handles daylight saving and clips live timers", checks.reportClipsLiveTimeAndHandlesDaylightSaving),
    ("Long reports retain full totals beyond the daily chart", checks.longReportKeepsFullTotalsWhileLimitingDailyChart),
    ("Switching projects closes the old timer", checks.switchStopsPreviousTimer),
    ("Idle review trims and restores away time", checks.idleCutsBackToLastInputAndReviewCanRestoreTime),
    ("Crash recovery trusts saved heartbeat", checks.crashRecoveryOnlyTrustsLastHeartbeat),
    ("Parent totals clip at range boundaries", checks.parentRollupAndIntervalClipping),
    ("Overlap detection permits adjacent entries", checks.adjacentEntriesAllowedButOverlapsRejected),
    ("Calendar weeks handle daylight saving", checks.daylightSavingWeekHasCalendarBoundaries),
    ("Pre-session inactivity does not pause a new timer", checks.idleBeforeSessionDoesNotPauseNewTimer),
    ("Idle review uses actual return rather than detection time", checks.returnReviewUsesActualReturnTime),
    ("Complete notebook survives an atomic disk save", checks.notebookSurvivesDiskRoundTrip),
    ("Overlap warnings leave records unchanged until confirmation", checks.overrideRequiresConfirmationAndCancelChangesNothing),
    ("Override trims only overlapping time", checks.overrideTrimsOnlyOverlappingTime),
    ("Override preserves both sides of a split entry", checks.overrideSplitsAnEntryAndPreservesBothSides),
    ("Override handles multiple and fully covered entries", checks.overrideHandlesMultipleAndFullyCoveredEntries),
    ("Editing excludes its own original entry from conflicts", checks.overridingAnEditDoesNotConflictWithItself),
    ("Override preserves the running timer and validates first", checks.overridePreservesRunningTimerAndValidatesBeforeMutation),
    ("Idle sampling includes keyboard and mouse input from all apps", checks.idleSamplingIncludesInputFromEveryApp),
    ("Delayed background updates do not pause active work", checks.delayedBackgroundUpdateDoesNotPauseActiveWork),
    ("Actual computer inactivity still pauses at last input", checks.actualComputerInactivityStillPausesAtLastInput),
    ("Discard removes paused parts but preserves projects and other sessions", checks.discardPausedSessionKeepsProjectsAndOtherSessions),
    ("Discard cannot remove a running session", checks.discardCannotRemoveARunningSession),
    ("Discard preserves pending review and ignores unknown sessions", checks.discardCannotBypassReviewOrTargetUnknownSession)
]
var failures = 0
for (name, check) in cases {
    do { try check(); print("PASS: \(name)") }
    catch { failures += 1; print("FAIL: \(name): \(error)") }
}
print("\(cases.count - failures)/\(cases.count) checks passed")
if failures > 0 { exit(1) }
