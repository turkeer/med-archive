import SwiftData
import SwiftUI

/// The home screen: a readiness headline for the committee in progress, what is
/// on today, a little momentum, and — the point of it all — a triage list that
/// shows only what you are behind on.
///
/// It is the cockpit, not the archive. The Komiteler screen answers "are the
/// slides here?"; this one adds a second axis the rest of the app never stores —
/// "have I studied it?" — and is the only place that axis is shown or set, by
/// choice: the other screens stay clean for editing and reference.
///
/// Its rows are its own (`WorkspaceTopicRow`) rather than the shared
/// `LectureLinkList`, precisely so the study tick lives here and nowhere else.
struct WorkspaceView: View {
    @Query private var allLectures: [Lecture]
    @Query private var committees: [Committee]

    /// The triage list defaults to what needs doing — that is the whole reason
    /// the screen exists. "Hepsi" is there when you want the full picture.
    @State private var scope: TriageScope = .behind

    private let calendar = Calendar.current

    var body: some View {
        Form {
            readinessHero

            today

            momentum

            activeCommitteeSummary
        }
        .formStyle(.grouped)
        .navigationTitle(L.workspace)
    }

    // MARK: Readiness headline

    /// The one prominent line: which committee, how long to its end, and how
    /// much of it is still unstudied or missing slides. The summary of the
    /// summary, so opening the app answers "how ready am I?" before any scroll.
    @ViewBuilder
    private var readinessHero: some View {
        if let committee = activeCommittee {
            let tally = progress(of: committee)

            Section {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(committee.fullLabel.isEmpty ? L.unnamed : committee.fullLabel)
                            .font(.headline)

                        Spacer()

                        Text(status(of: committee))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text(readinessLine(tally))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    /// "18 konu çalışılmadı · 3 konu slaytsız", or a clean-slate line when there
    /// is nothing behind. Only taught topics are in the figures.
    private func readinessLine(_ tally: Tally) -> String {
        guard tally.due > 0 else {
            return L.pick("Henüz işlenen konu yok.", "No topics taught yet.")
        }

        let unstudied = tally.due - tally.studied
        let missing = tally.due - tally.slides

        var parts: [String] = []
        if unstudied > 0 {
            parts.append(L.pick("\(unstudied) konu çalışılmadı", "\(unstudied) topics not studied"))
        } else {
            parts.append(L.pick("işlenen her konu çalışıldı", "every taught topic studied"))
        }
        if missing > 0 {
            parts.append(L.pick("\(missing) konu slaytsız", "\(missing) without slides"))
        }

        return parts.joined(separator: " · ")
    }

    // MARK: Today

    /// Today's topics, or — when today is free — the next day that has any, so a
    /// blank day still points somewhere.
    @ViewBuilder
    private var today: some View {
        let groups = todaysGroups

        if !groups.isEmpty {
            Section("\(L.pick("Bugün", "Today")) (\(groups.count))") {
                ForEach(groups) { group in
                    WorkspaceTopicRow(group: group, leading: slot(of: group), showCourse: true)
                }
            }
        } else {
            Section(L.pick("Bugün", "Today")) {
                Text(L.pick("Bugün planlı ders yok.", "No lessons scheduled today."))
                    .foregroundStyle(.secondary)
            }

            if let next = nextDayGroups {
                Section(L.pick("Sıradaki gün — ", "Next day — ")
                    + L.format(next.day, Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide))) {
                    ForEach(next.groups) { group in
                        WorkspaceTopicRow(group: group, leading: slot(of: group), showCourse: true)
                    }
                }
            }
        }
    }

    private var todaysGroups: [LectureGroup] {
        let today = calendar.startOfDay(for: Date())
        let todays = allLectures.filter { calendar.isDate($0.date, inSameDayAs: today) }
        return LectureGrouping.groups(of: todays, sort: .oldestFirst)
    }

    private var nextDay: Date? {
        let today = calendar.startOfDay(for: Date())
        return allLectures
            .map { calendar.startOfDay(for: $0.date) }
            .filter { $0 > today }
            .min()
    }

    private var nextDayGroups: (day: Date, groups: [LectureGroup])? {
        guard let nextDay else { return nil }
        let next = allLectures.filter { calendar.isDate($0.date, inSameDayAs: nextDay) }
        let groups = LectureGrouping.groups(of: next, sort: .oldestFirst)
        return groups.isEmpty ? nil : (nextDay, groups)
    }

    private func slot(of group: LectureGroup) -> String {
        LectureGrouping.slotLabel(for: group.lectures)
    }

    // MARK: Momentum

    /// A light line of encouragement off the study marks — simple, and the one
    /// use of the `studiedAt` dates beyond the tick itself.
    private var momentum: some View {
        Section {
            Text(momentumLine)
                .font(.callout)
        } header: {
            Text(L.pick("Momentum", "Momentum"))
        }
    }

    private var momentumLine: String {
        let startOfToday = calendar.startOfDay(for: Date())
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? startOfToday

        let week = studiedCount(since: startOfWeek)
        guard week > 0 else {
            return L.pick("Bu hafta henüz konu çalışmadın.", "No topics studied this week yet.")
        }

        let todayCount = studiedCount(since: startOfToday)
        return L.pick(
            "Bu hafta \(week) konu · bugün \(todayCount) konu çalıştın.",
            "\(week) topics this week · \(todayCount) today."
        )
    }

    /// How many topics were last marked studied on or after `date`.
    private func studiedCount(since date: Date) -> Int {
        LectureGrouping.groups(of: allLectures).filter { group in
            guard let last = group.lectures.compactMap(\.studiedAt).max() else { return false }
            return last >= date
        }
        .count
    }

    // MARK: Active committee — triage

    @ViewBuilder
    private var activeCommitteeSummary: some View {
        if let committee = activeCommittee {
            let tally = progress(of: committee)
            let runs = courseRuns(of: committee)

            Section {
                if tally.due > 0 {
                    WorkspaceProgressRow(label: L.pick("Slayt", "Slides"), done: tally.slides, total: tally.due)
                    WorkspaceProgressRow(label: L.pick("Çalışıldı", "Studied"), done: tally.studied, total: tally.due)
                }

                Picker(L.pick("Göster", "Show"), selection: $scope) {
                    ForEach(TriageScope.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text(L.pick("Aktif komite", "Active committee"))
            } footer: {
                Text(L.pick(
                    "Geride kalanlar: günü gelmiş ama çalışılmamış ya da slaytı eksik konular.",
                    "Behind: taught topics that are unstudied or missing slides."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if runs.isEmpty {
                Section {
                    Text(scope == .behind
                        ? L.pick("Geride kalan konu yok. 🎉", "Nothing behind. 🎉")
                        : L.pick("Bu komitede oturum yok.", "No sessions in this committee."))
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(runs) { run in
                    Section(run.name) {
                        ForEach(run.groups) { group in
                            WorkspaceTopicRow(group: group, leading: date(of: group), showCourse: false)
                        }
                    }
                }
            }
        } else {
            Section(L.pick("Aktif komite", "Active committee")) {
                Text(L.pick("Henüz komite yok.", "No committees yet."))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The committee in progress today; failing that the nearest one still to
    /// come; failing that the most recent one that has ended.
    private var activeCommittee: Committee? {
        let today = calendar.startOfDay(for: Date())

        if let current = committees.first(where: { $0.covers(today, calendar: calendar) }) {
            return current
        }

        let upcoming = committees
            .filter { calendar.startOfDay(for: $0.startDate) > today }
            .min { $0.startDate < $1.startDate }
        if let upcoming { return upcoming }

        return committees.max { $0.endDate < $1.endDate }
    }

    /// How many of the committee's taught topics have slides, and how many are
    /// studied. Only topics whose day has come are counted, matching the
    /// Komiteler screen: a lesson next week is not a lesson you are behind on.
    private struct Tally {
        var due = 0
        var slides = 0
        var studied = 0
    }

    private func progress(of committee: Committee) -> Tally {
        let today = calendar.startOfDay(for: Date())
        var tally = Tally()

        for group in LectureGrouping.groups(of: committee.lectures) {
            guard calendar.startOfDay(for: group.first.date) <= today else { continue }
            tally.due += 1
            if LectureGrouping.slidesAccountedFor(group.lectures) { tally.slides += 1 }
            if LectureGrouping.isStudied(group.lectures) { tally.studied += 1 }
        }

        return tally
    }

    /// Whether a topic is behind: its day has come and it is still unstudied or
    /// still has no slides. Topics ahead are never behind.
    private func isBehind(_ group: LectureGroup) -> Bool {
        let today = calendar.startOfDay(for: Date())
        guard calendar.startOfDay(for: group.first.date) <= today else { return false }

        let studied = LectureGrouping.isStudied(group.lectures)
        let hasSlides = LectureGrouping.slidesAccountedFor(group.lectures)
        return !studied || !hasSlides
    }

    private struct CourseRun: Identifiable {
        let name: String
        let groups: [LectureGroup]
        var id: String { name }
    }

    private func courseRuns(of committee: Committee) -> [CourseRun] {
        let groups = LectureGrouping.groups(of: committee.lectures, sort: .oldestFirst)
            .filter { scope == .all || isBehind($0) }

        return Dictionary(grouping: groups) {
            $0.first.course?.name ?? L.pick("Dersi belirtilmemiş", "No course set")
        }
        .map { CourseRun(name: $0.key, groups: $0.value) }
        .sorted { $0.name < $1.name }
    }

    private func date(of group: LectureGroup) -> String {
        group.first.date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    /// "bitişe 9 gün", "başlamasına 3 gün", or "bitti" — where the committee
    /// sits relative to today, in whole days.
    private func status(of committee: Committee) -> String {
        let today = calendar.startOfDay(for: Date())
        let start = calendar.startOfDay(for: committee.startDate)
        let end = calendar.startOfDay(for: committee.endDate)

        if today < start {
            let days = calendar.dateComponents([.day], from: today, to: start).day ?? 0
            return L.pick("başlamasına \(days) gün", "\(days) days to start")
        }
        if today > end {
            return L.pick("bitti", "finished")
        }

        let days = calendar.dateComponents([.day], from: today, to: end).day ?? 0
        return L.pick("bitişe \(days) gün", "\(days) days left")
    }
}

/// Whether the triage list shows only what is behind, or everything.
private enum TriageScope: String, CaseIterable, Identifiable {
    case behind
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .behind: return L.pick("Geride kalanlar", "Behind")
        case .all:    return L.pick("Hepsi", "All")
        }
    }
}

/// A topic in the workspace: a tick to mark it studied, and the topic itself,
/// which hands off to Konular like every other lecture row. The tick is the
/// one piece of interface that touches study state, and it lives only here.
private struct WorkspaceTopicRow: View {
    let group: LectureGroup

    /// The grey leading column: the day's periods on the Bugün list, the date in
    /// the committee breakdown.
    var leading: String
    var showCourse: Bool

    @Environment(AppNavigation.self) private var nav

    private var studied: Bool { LectureGrouping.isStudied(group.lectures) }
    private var hasFiles: Bool { group.lectures.contains { !$0.files.isEmpty } }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                LectureGrouping.setStudied(!studied, for: group.lectures)
            } label: {
                Image(systemName: studied ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(studied ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(studied
                ? L.pick("Çalışıldı — işareti kaldır", "Studied — clear the mark")
                : L.pick("Çalışıldı olarak işaretle", "Mark as studied"))

            Button {
                nav.show(group.first)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(leading)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(width: 104, alignment: .leading)

                    VStack(alignment: .leading, spacing: 1) {
                        meta

                        Text(group.first.displayTitle)
                            .strikethrough(studied, color: .secondary)
                            .foregroundStyle(studied ? .secondary : .primary)
                    }

                    Spacer()

                    if hasFiles {
                        Image(systemName: "paperclip")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var meta: some View {
        let lessons = LectureGrouping.lessonCount(of: group.lectures)
        let showName = showCourse && group.first.course != nil && group.first.hasTopic

        if showName || group.first.format != .theoretical || lessons > 1 {
            HStack(spacing: 5) {
                if showName, let course = group.first.course {
                    Text(course.name)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color(hex: course.colorHex))
                }

                FormatBadge(format: group.first.format)

                if lessons > 1 {
                    Text(L.lessonCount(lessons))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.16), in: Capsule())
                }
            }
        }
    }
}

/// A labelled bar — "Slayt 8/23" — for the committee's two progress axes.
/// Green only when the fraction is full, the one state worth spotting.
private struct WorkspaceProgressRow: View {
    let label: String
    let done: Int
    let total: Int

    private var fraction: Double {
        total == 0 ? 0 : Double(done) / Double(total)
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)

            Capsule()
                .fill(Color.secondary.opacity(0.22))
                .frame(height: 5)
                .overlay(alignment: .leading) {
                    GeometryReader { geometry in
                        Capsule()
                            .fill(done == total ? Color.green : Color.accentColor)
                            .frame(width: geometry.size.width * fraction)
                    }
                }

            Text("\(done)/\(total)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .trailing)
        }
    }
}
