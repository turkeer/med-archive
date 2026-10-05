import SwiftData
import SwiftUI

/// The week as a timetable: weekdays across, the nine periods down, each
/// session filled with its course's colour.
///
/// Laid out as a column per day rather than a row per period, which is what
/// lets a double period be one tall block instead of two cells that read as
/// separate lessons. `DayTimetable` guarantees the spans always add up to nine
/// periods, so every column keeps the same height and the rows stay aligned
/// with the time column on the left.
struct CalendarWeekView: View {
    @Binding var selectedDay: Date?
    @Binding var visibleMonth: Date

    @Query private var lectures: [Lecture]

    @Environment(AppNavigation.self) private var nav
    @Environment(\.modelContext) private var context

    @State private var newLectureRequest: NewLectureRequest?

    private let calendar = Calendar.current
    private let timeColumnWidth: CGFloat = 56
    private let rowHeight: CGFloat = 46
    private let rowSpacing: CGFloat = 3

    private var grid: WeekGrid {
        WeekGrid(containing: selectedDay ?? Date())
    }

    /// Weekdays always; a weekend day only when something is scheduled on it,
    /// so a one-off Saturday session is never hidden.
    private var visibleDays: [Date] {
        grid.weekdays + grid.weekend.filter { !dayLectures(on: $0).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    dayHeaderRow

                    HStack(alignment: .top, spacing: 3) {
                        timeColumn

                        ForEach(visibleDays, id: \.self) { day in
                            dayColumn(day)
                                .frame(maxWidth: .infinity)
                        }
                    }

                    offTimetableRow
                }
                .padding(12)
            }
        }
        .navigationTitle("Hafta")
        .navigationSubtitle(grid.title)
        .sheet(item: $newLectureRequest) { request in
            NewLectureSheet(initialDate: request.day, initialSlot: request.slot)
        }
    }

    // MARK: Chrome

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                select(day: grid.adding(weeks: -1))
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .help("Önceki hafta")

            Button {
                select(day: grid.adding(weeks: 1))
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .help("Sonraki hafta")

            Text(grid.title)
                .font(.headline)

            Spacer()

            Button("Bu hafta") {
                select(day: Date())
            }
            .buttonStyle(.borderless)
        }
    }

    private var dayHeaderRow: some View {
        HStack(spacing: 3) {
            Spacer()
                .frame(width: timeColumnWidth)

            ForEach(visibleDays, id: \.self) { day in
                Button {
                    select(day: day)
                } label: {
                    VStack(spacing: 1) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Text(day.formatted(.dateTime.day()))
                            .font(.callout.monospacedDigit().weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
                    .background(headerBackground(for: day), in: RoundedRectangle(cornerRadius: 5))
                    .overlay {
                        if calendar.isDateInToday(day) {
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(Color.accentColor, lineWidth: 1.5)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func headerBackground(for day: Date) -> Color {
        guard let selectedDay, calendar.isDate(day, inSameDayAs: selectedDay) else {
            return Color.secondary.opacity(0.08)
        }
        return Color.accentColor.opacity(0.22)
    }

    private var timeColumn: some View {
        VStack(spacing: rowSpacing) {
            ForEach(LessonSlot.all) { slot in
                VStack(alignment: .trailing, spacing: 0) {
                    Text(slot.label)
                        .font(.caption2.weight(.semibold))
                    Text(TimeOfDay.text(slot.start))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .frame(width: timeColumnWidth, height: rowHeight, alignment: .trailing)
            }
        }
    }

    // MARK: The grid

    private func dayColumn(_ day: Date) -> some View {
        // Computed once per day, not once per cell.
        let parts = LectureGrouping.partNumbers(for: dayLectures(on: day))

        return VStack(spacing: rowSpacing) {
            ForEach(DayTimetable.segments(for: timetabled(on: day))) { segment in
                segmentView(segment, on: day, parts: parts)
                    .frame(height: height(ofSpan: segment.span))
            }
        }
    }

    @ViewBuilder
    private func segmentView(
        _ segment: DaySegment,
        on day: Date,
        parts: [PersistentIdentifier: (index: Int, total: Int)]
    ) -> some View {
        if segment.isFree {
            Button {
                newLectureRequest = NewLectureRequest(day: day, slot: segment.slot)
            } label: {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.secondary.opacity(0.07))
                    .overlay {
                        Image(systemName: "plus")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
            }
            .buttonStyle(.plain)
            .help("\(segment.slot.longLabel) — oturum ekle")
        } else {
            VStack(spacing: 2) {
                ForEach(segment.lectures) { lecture in
                    LectureBlock(
                        lecture: lecture,
                        span: segment.span,
                        part: parts[lecture.persistentModelID],
                        open: { nav.show(lecture) },
                        fillDown: fillDownRange(for: lecture, on: day) == nil
                            ? nil
                            : { fillDown(lecture, on: day) }
                    )
                }
            }
        }
    }

    /// A run of `span` periods, including the gaps the rows would have had.
    /// Nine periods always come to the same total, whatever the arrangement.
    private func height(ofSpan span: Int) -> CGFloat {
        CGFloat(span) * rowHeight + CGFloat(span - 1) * rowSpacing
    }

    /// Seminars and exams have no period, so they get a row under the grid
    /// rather than being left out of the week.
    @ViewBuilder
    private var offTimetableRow: some View {
        if visibleDays.contains(where: { !offTimetable(on: $0).isEmpty }) {
            HStack(alignment: .top, spacing: 3) {
                Text("program\ndışı")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .frame(width: timeColumnWidth, alignment: .trailing)

                ForEach(visibleDays, id: \.self) { day in
                    offTimetableColumn(day)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
            }
        }
    }

    // MARK: Actions

    /// Keeps the month grid on the left in step: selecting a day in another
    /// month moves that grid too.
    private func select(day: Date) {
        let target = calendar.startOfDay(for: day)
        selectedDay = target

        if !calendar.isDate(target, equalTo: visibleMonth, toGranularity: .month) {
            visibleMonth = target
        }
    }

    /// Where a copy of this lecture would go: the same number of periods,
    /// immediately after, and only when all of them are free.
    private func fillDownRange(for lecture: Lecture, on day: Date) -> (start: Int, end: Int)? {
        let span = LessonSlot.span(start: lecture.startMinutes, end: lecture.endMinutes)
        guard let last = span.last else { return nil }

        let count = span.count
        let firstIndex = last.number          // 0-based index of the period after `last`
        guard firstIndex + count <= LessonSlot.all.count else { return nil }

        let targets = Array(LessonSlot.all[firstIndex ..< firstIndex + count])
        let taken = dayLectures(on: day).contains { other in
            targets.contains { $0.overlaps(start: other.startMinutes, end: other.endMinutes) }
        }
        guard !taken else { return nil }

        return (targets[0].start, targets[count - 1].end)
    }

    /// Copies a lecture into the periods that follow as a **separate** record.
    ///
    /// One topic often runs over two consecutive periods that the school still
    /// counts as two lessons, so this duplicates rather than extends. Notes and
    /// files stay behind — those belong to the session, not the subject.
    private func fillDown(_ lecture: Lecture, on day: Date) {
        guard let range = fillDownRange(for: lecture, on: day) else { return }

        let copy = Lecture(
            title: lecture.title,
            date: lecture.date,
            startMinutes: range.start,
            endMinutes: range.end,
            format: lecture.format
        )
        context.insert(copy)

        copy.course = lecture.course
        copy.instructor = lecture.instructor
        copy.committee = lecture.committee
        copy.tags = lecture.tags
    }

    // MARK: Data

    private func offTimetableColumn(_ day: Date) -> some View {
        let parts = LectureGrouping.partNumbers(for: dayLectures(on: day))

        return VStack(spacing: 3) {
            ForEach(offTimetable(on: day)) { lecture in
                LectureBlock(
                    lecture: lecture,
                    span: 1,
                    part: parts[lecture.persistentModelID],
                    open: { nav.show(lecture) },
                    fillDown: nil
                )
                .frame(height: rowHeight)
            }
        }
    }

    private func dayLectures(on day: Date) -> [Lecture] {
        let target = calendar.startOfDay(for: day)
        return lectures.filter { calendar.startOfDay(for: $0.date) == target }
    }

    private func timetabled(on day: Date) -> [Lecture] {
        dayLectures(on: day).filter {
            !LessonSlot.span(start: $0.startMinutes, end: $0.endMinutes).isEmpty
        }
    }

    private func offTimetable(on day: Date) -> [Lecture] {
        dayLectures(on: day).filter {
            LessonSlot.span(start: $0.startMinutes, end: $0.endMinutes).isEmpty
        }
    }
}

/// A session as a coloured block. Its content is centred, so a block covering
/// two or three periods uses the room instead of crowding the top.
private struct LectureBlock: View {
    let lecture: Lecture
    let span: Int

    /// Which of several parts of one topic this is, when there are several.
    let part: (index: Int, total: Int)?

    let open: () -> Void

    /// Set when the periods right after this one are free, and pressing it
    /// copies the lecture into them.
    let fillDown: (() -> Void)?

    private var color: Color {
        Color(hex: lecture.course?.colorHex ?? "8B8D98")
    }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(color)
                    .frame(width: 3)

                VStack(spacing: 1) {
                    HStack(spacing: 3) {
                        Text(lecture.course?.name ?? "—")
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)

                        FormatBadge(format: lecture.format, tint: color)
                    }

                    if lecture.hasTopic {
                        Text(topicText)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(span >= 2 ? 3 : 2)
                            .multilineTextAlignment(.center)
                    }

                    // Only a taller block has room for this without crowding.
                    if span >= 2, let instructor = lecture.instructor {
                        Text(instructor.name)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(color.opacity(0.26), in: RoundedRectangle(cornerRadius: 5))
            .overlay(alignment: .bottomTrailing) {
                if let fillDown {
                    Button(action: fillDown) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(color)
                            .background(Circle().fill(.background))
                    }
                    .buttonStyle(.plain)
                    .help("Aynısını bir sonraki derse ekle")
                    .padding(2)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help(helpText)
    }

    /// "Introduction to Anatomy (2)" — the school counts the parts as
    /// separate lessons, so the block says which one this is instead of
    /// pretending the two are one long session.
    private var topicText: String {
        guard let part else { return lecture.title }
        return "\(lecture.title) (\(part.index))"
    }

    private var helpText: String {
        [
            lecture.course?.name,
            part.map { "\($0.index)/\($0.total). ders" },
            lecture.hasTopic ? lecture.title : nil,
            lecture.format.title,
            lecture.scheduleText.isEmpty ? nil : lecture.scheduleText,
            lecture.instructor?.displayName,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}
