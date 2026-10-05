import SwiftData
import SwiftUI

/// What needs attention, on one screen.
///
/// Every row is a way in, not a statistic. A summary made of numbers stops
/// being read after a week; one where "7 topics have no slides" opens the list
/// of those seven keeps earning its place. The filter it hands over is the
/// same one Konular has always had, so nothing here is a second way of asking
/// the same question.
/// The day's lessons, in the middle column where every other list lives.
struct HomeDayColumn: View {
    @Query private var lectures: [Lecture]

    private var today: Date {
        Calendar.current.startOfDay(for: Date())
    }

    var body: some View {
        Form {
            daySection
        }
        .formStyle(.grouped)
        .navigationTitle(L.pick("Özet", "Summary"))
    }

    /// Today when there is anything on, otherwise the next day that has
    /// something. A summary opening on an empty Sunday would be useless on the
    /// one morning you most want to see what is coming.
    private var shownDay: Date? {
        let days = Set(lectures.map { Calendar.current.startOfDay(for: $0.date) })
        if days.contains(today) { return today }
        return days.filter { $0 > today }.min()
    }

    private var dayLectures: [Lecture] {
        guard let shownDay else { return [] }
        return lectures
            .filter { Calendar.current.isDate($0.date, inSameDayAs: shownDay) }
            .sorted { ($0.startMinutes ?? 0) < ($1.startMinutes ?? 0) }
    }

    @ViewBuilder
    private var daySection: some View {
        if let shownDay {
            LectureLinkList(
                lectures: dayLectures,
                title: dayTitle(shownDay),
                dayMode: true
            )
        } else {
            Section(L.pick("Bugün", "Today")) {
                Text(L.pick("Kayıtlı oturum yok.", "No sessions recorded."))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func dayTitle(_ day: Date) -> String {
        let date = L.format(day, Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide))

        if day == today {
            return L.pick("Bugün", "Today") + " · \(date)"
        }
        return L.pick("Sıradaki ders günü", "Next day with lessons") + " · \(date)"
    }
}

struct HomeView: View {
    @Environment(AppNavigation.self) private var nav
    @Environment(LibraryRoot.self) private var library

    @Query private var committees: [Committee]
    @Query private var fileRecords: [LectureFile]

    /// Checked against the disk, so it runs when the screen appears and when
    /// asked — not on every redraw.
    @State private var brokenCount: Int?
    @State private var isShowingBroken = false

    private var today: Date {
        Calendar.current.startOfDay(for: Date())
    }

    var body: some View {
        Form {
            committeeSection
            filesSection
        }
        .formStyle(.grouped)
        .navigationTitle(L.pick("Özet", "Summary"))
        .onAppear(perform: refreshBroken)
        .sheet(isPresented: $isShowingBroken) {
            BrokenLinksSheet()
        }
    }

    // MARK: Committee

    /// The one running now, or the next one to start. A committee that ended
    /// last month is not what you came to the summary for.
    private var currentCommittee: Committee? {
        if let covering = committees.first(where: { $0.covers(today) }) {
            return covering
        }
        return committees.filter { $0.startDate > today }.min { $0.startDate < $1.startDate }
    }

    @ViewBuilder
    private var committeeSection: some View {
        if let committee = currentCommittee {
            Section {
                LabeledContent(L.pick("Tarihler", "Dates")) {
                    Text(committee.dateRangeText)
                }

                LabeledContent(daysLabel(for: committee)) {
                    Text(daysText(for: committee))
                }

                row(
                    label: L.pick("İşlenen ders", "Lessons recorded"),
                    value: "\(committee.lectures.count)"
                ) {
                    var filter = LectureFilter()
                    filter.committeeID = committee.persistentModelID
                    nav.showTopics(filter)
                }

                row(
                    label: L.pick("Slaytı eksik konu", "Topics with no slides"),
                    value: "\(gaps(in: committee).reduce(0) { $0 + $1.count })",
                    isWarning: !gaps(in: committee).isEmpty
                ) {
                    var filter = LectureFilter()
                    filter.committeeID = committee.persistentModelID
                    filter.missingFilesOnly = true
                    nav.showTopics(filter)
                }

                // Which course to go looking for, rather than only how many.
                // "Six missing" is a worry; "four of them Anatomy" is a plan.
                ForEach(gaps(in: committee)) { gap in
                    row(label: "— " + gap.name, value: "\(gap.count)") {
                        var filter = LectureFilter()
                        filter.committeeID = committee.persistentModelID
                        filter.courseID = gap.courseID
                        filter.missingFilesOnly = true
                        nav.showTopics(filter)
                    }
                }
            } header: {
                Text(committee.fullLabel.isEmpty ? L.committee : committee.fullLabel)
            } footer: {
                if committee.startDate > today {
                    Text(L.pick("Bu komite henüz başlamadı.", "This committee has not started yet."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Section(L.committee) {
                Text(L.pick(
                    "Tarih aralığı bugünü kapsayan bir komite yok.",
                    "No committee's date range covers today."
                ))
                .foregroundStyle(.secondary)
            }
        }
    }

    private func daysLabel(for committee: Committee) -> String {
        committee.startDate > today
            ? L.pick("Başlamasına", "Starts in")
            : L.pick("Kalan gün", "Days left")
    }

    private func daysText(for committee: Committee) -> String {
        let target = committee.startDate > today ? committee.startDate : committee.endDate
        let days = Calendar.current.dateComponents([.day], from: today, to: target).day ?? 0

        if days < 0 { return L.pick("bitti", "over") }
        if days == 0 { return L.pick("son gün", "last day") }
        return L.pick("\(days) gün", days == 1 ? "1 day" : "\(days) days")
    }

    /// Topics with nothing attached, counted per course.
    ///
    /// Topics, not records: a subject taught across two periods shares its
    /// slides, so it is one thing to find, not two.
    private struct CourseGap: Identifiable {
        let courseID: PersistentIdentifier?
        let name: String
        let count: Int

        var id: String { name }
    }

    private func gaps(in committee: Committee) -> [CourseGap] {
        let groups = LectureGrouping.groups(of: committee.lectures)
            .filter { group in group.lectures.allSatisfy { $0.files.isEmpty } }

        var tally: [String: CourseGap] = [:]

        for group in groups {
            let course = group.first.course
            let name = course?.name ?? L.pick("Dersi belirtilmemiş", "No course set")
            let previous = tally[name]?.count ?? 0

            tally[name] = CourseGap(
                courseID: course?.persistentModelID,
                name: name,
                count: previous + 1
            )
        }

        return tally.values.sorted { one, other in
            if one.count != other.count { return one.count > other.count }
            return one.name.localizedStandardCompare(other.name) == .orderedAscending
        }
    }

    // MARK: Files

    @ViewBuilder
    private var filesSection: some View {
        Section {
            if let brokenCount {
                if brokenCount == 0 {
                    Label(
                        L.pick("Bütün dosya bağları sağlam.", "Every file link resolves."),
                        systemImage: "checkmark.circle"
                    )
                    .foregroundStyle(.secondary)
                } else {
                    row(
                        label: L.pick("Yeri değişmiş dosya", "Files that have moved"),
                        value: "\(brokenCount)",
                        isWarning: true
                    ) {
                        isShowingBroken = true
                    }
                }
            } else {
                Text(L.pick("Kontrol ediliyor…", "Checking…"))
                    .foregroundStyle(.secondary)
            }

            Button(L.pick("Yeniden kontrol et", "Check again"), action: refreshBroken)
                .buttonStyle(.link)
        } header: {
            Text(L.files)
        } footer: {
            Text(L.pick(
                "Uygulama dosyaların yerini saklar, kopyasını tutmaz. Finder'da taşıdığın ya da adını değiştirdiğin bir dosyanın kaydı boşa düşer — buradan yeni yerini gösterebilirsin.",
                "The app remembers where files are, it does not keep copies. A file you move or rename in Finder leaves its record pointing at nothing — you can show it the new location from here."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func refreshBroken() {
        brokenCount = FileHealth.broken(among: fileRecords, library: library).count
    }

    // MARK: A row that goes somewhere

    private func row(
        label: String,
        value: String,
        isWarning: Bool = false,
        open: @escaping () -> Void
    ) -> some View {
        Button(action: open) {
            HStack {
                Text(label)
                    .foregroundStyle(Color.primary)

                Spacer()

                Text(value)
                    .monospacedDigit()
                    .foregroundStyle(isWarning ? Color.orange : Color.secondary)

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
