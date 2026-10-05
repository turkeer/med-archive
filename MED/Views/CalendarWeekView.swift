import SwiftData
import SwiftUI

/// The week as a timetable: weekdays across, the nine periods down, each
/// session filled with its course's colour.
///
/// It lives in the wide trailing column, with the month grid staying narrow on
/// its left — five columns of lectures do not fit a list-width column. Picking
/// a day in the month grid moves this view to that week.
struct CalendarWeekView: View {
    @Binding var selectedDay: Date?
    @Binding var visibleMonth: Date

    @Query private var lectures: [Lecture]

    @Environment(AppNavigation.self) private var nav

    @State private var isAddingLecture = false
    @State private var pendingDay: Date?
    @State private var pendingSlot: LessonSlot?
    @State private var newLectureSeed = UUID()

    private let calendar = Calendar.current
    private let timeColumnWidth: CGFloat = 56

    private var grid: WeekGrid {
        WeekGrid(containing: selectedDay ?? Date())
    }

    /// Weekdays always; a weekend day only when something is scheduled on it,
    /// so a one-off Saturday session is never hidden.
    private var visibleDays: [Date] {
        grid.weekdays + grid.weekend.filter { !timetabled(on: $0).isEmpty || !offTimetable(on: $0).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(spacing: 3) {
                    dayHeaderRow

                    ForEach(LessonSlot.all) { slot in
                        slotRow(slot)
                    }

                    offTimetableRow
                }
                .padding(12)
            }
        }
        .navigationTitle("Hafta")
        .navigationSubtitle(grid.title)
        .sheet(isPresented: $isAddingLecture) {
            NewLectureSheet(
                initialDate: pendingDay ?? Date(),
                initialSlot: pendingSlot
            )
            .id(newLectureSeed)
        }
    }

    // MARK: Chrome

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                move(weeks: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .help("Önceki hafta")

            Button {
                move(weeks: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .help("Sonraki hafta")

            Text(grid.title)
                .font(.headline)

            Spacer()

            Button("Bu hafta") {
                select(day: calendar.startOfDay(for: Date()))
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

    private func slotRow(_ slot: LessonSlot) -> some View {
        HStack(spacing: 3) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(slot.label)
                    .font(.caption2.weight(.semibold))
                Text(TimeOfDay.text(slot.start))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: timeColumnWidth, alignment: .trailing)

            ForEach(visibleDays, id: \.self) { day in
                WeekCell(
                    slot: slot,
                    lectures: timetabled(on: day),
                    open: { nav.show($0) },
                    add: { add(on: day, in: slot) }
                )
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// Seminars and exams have no period, so they get a row of their own under
    /// the grid rather than being left out of the week.
    @ViewBuilder
    private var offTimetableRow: some View {
        if visibleDays.contains(where: { !offTimetable(on: $0).isEmpty }) {
            HStack(spacing: 3) {
                Text("program\ndışı")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .frame(width: timeColumnWidth, alignment: .trailing)

                ForEach(visibleDays, id: \.self) { day in
                    VStack(spacing: 3) {
                        ForEach(offTimetable(on: day)) { lecture in
                            LectureBlock(lecture: lecture) {
                                nav.show(lecture)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 24, alignment: .top)
                }
            }
            .padding(.top, 6)
        }
    }

    // MARK: Actions

    private func move(weeks: Int) {
        select(day: grid.adding(weeks: weeks))
    }

    /// Keeps the month grid on the left in step: selecting a day in another
    /// month moves that grid too.
    private func select(day: Date) {
        let target = calendar.startOfDay(for: day)
        selectedDay = target

        if !calendar.isDate(target, equalTo: visibleMonth, toGranularity: .month) {
            visibleMonth = target
        }
    }

    private func add(on day: Date, in slot: LessonSlot) {
        pendingDay = day
        pendingSlot = slot
        newLectureSeed = UUID()
        isAddingLecture = true
    }

    // MARK: Data

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

/// One cell of the week grid: what starts in this period, a continuation of a
/// double period, or an empty slot waiting to be filled.
private struct WeekCell: View {
    let slot: LessonSlot
    let lectures: [Lecture]
    let open: (Lecture) -> Void
    let add: () -> Void

    private var starting: [Lecture] {
        lectures.filter { $0.startMinutes == slot.start }
    }

    private var covering: Lecture? {
        lectures.first { slot.overlaps(start: $0.startMinutes, end: $0.endMinutes) }
    }

    var body: some View {
        if !starting.isEmpty {
            VStack(spacing: 2) {
                ForEach(starting) { lecture in
                    LectureBlock(lecture: lecture) {
                        open(lecture)
                    }
                }
            }
        } else if let covering {
            // Same colour, no text: a double period reads as one block.
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(hex: covering.course?.colorHex ?? "8B8D98").opacity(0.22))
                .frame(height: 42)
                .onTapGesture { open(covering) }
        } else {
            Button(action: add) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.secondary.opacity(0.07))
                    .frame(height: 42)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
            }
            .buttonStyle(.plain)
            .help("\(slot.longLabel) — oturum ekle")
        }
    }
}

/// A session as a coloured block: the course's colour fills it, a bar in the
/// full colour runs down the leading edge, and a lab is marked "P".
private struct LectureBlock: View {
    let lecture: Lecture
    let open: () -> Void

    private var color: Color {
        Color(hex: lecture.course?.colorHex ?? "8B8D98")
    }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(color)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 3) {
                        Text(lecture.course?.name ?? "—")
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)

                        FormatBadge(format: lecture.format, tint: color)
                    }

                    if lecture.hasTopic {
                        Text(lecture.title)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 42, alignment: .top)
            .background(color.opacity(0.26), in: RoundedRectangle(cornerRadius: 5))
            .contentShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help(helpText)
    }

    private var helpText: String {
        [
            lecture.course?.name,
            lecture.hasTopic ? lecture.title : nil,
            lecture.format.title,
            lecture.scheduleText.isEmpty ? nil : lecture.scheduleText,
            lecture.instructor?.displayName,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}
