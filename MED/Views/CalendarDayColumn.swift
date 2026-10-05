import SwiftUI
import SwiftData

/// The selected day, laid out as the school's nine periods. Empty periods
/// offer to fill themselves; a lecture row hands you off to that lecture on
/// the Konular screen, the same way the related screens do.
///
/// Weekends have no timetable, so they fall back to a plain list.
struct CalendarDayColumn: View {
    let day: Date?

    @Query private var lectures: [Lecture]

    @State private var newLectureRequest: NewLectureRequest?

    private let calendar = Calendar.current

    var body: some View {
        if let day {
            content(for: day)
        } else {
            SelectionPlaceholder(text: "Takvimden bir gün seç.")
        }
    }

    private func content(for day: Date) -> some View {
        Form {
            if calendar.isDateInWeekend(day) {
                LectureLinkList(lectures: dayLectures(on: day), dayMode: true)
            } else {
                Section("Ders saatleri") {
                    ForEach(LessonSlot.all) { slot in
                        SlotRow(slot: slot, lectures: timetabled(on: day)) {
                            add(on: day, in: slot)
                        }
                    }
                }

                // Seminars, exams, anything that does not sit on a period.
                if !offTimetable(on: day).isEmpty {
                    LectureLinkList(
                        lectures: offTimetable(on: day),
                        title: "Program dışı",
                        dayMode: true
                    )
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        .navigationSubtitle(day.formatted(.dateTime.year()))
        .toolbar {
            ToolbarItem {
                Button {
                    add(in: nil)
                } label: {
                    Label("Bu güne oturum ekle", systemImage: "plus")
                }
            }
        }
        .sheet(item: $newLectureRequest) { request in
            NewLectureSheet(initialDate: request.day, initialSlot: request.slot)
        }
    }

    private func add(on day: Date, in slot: LessonSlot?) {
        newLectureRequest = NewLectureRequest(day: day, slot: slot)
    }

    private func dayLectures(on day: Date) -> [Lecture] {
        let target = calendar.startOfDay(for: day)
        return lectures.filter { calendar.startOfDay(for: $0.date) == target }
    }

    /// Lectures whose times line up with a period.
    private func timetabled(on day: Date) -> [Lecture] {
        dayLectures(on: day).filter {
            !LessonSlot.span(start: $0.startMinutes, end: $0.endMinutes).isEmpty
        }
    }

    /// Everything else, including lectures with no time at all.
    private func offTimetable(on day: Date) -> [Lecture] {
        dayLectures(on: day).filter {
            LessonSlot.span(start: $0.startMinutes, end: $0.endMinutes).isEmpty
        }
    }
}

/// One period: what is in it, or an invitation to put something there.
private struct SlotRow: View {
    let slot: LessonSlot

    /// Only the day's timetabled lectures, so an off-grid seminar cannot
    /// make a period look occupied.
    let lectures: [Lecture]

    let add: () -> Void

    @Environment(AppNavigation.self) private var nav

    private var starting: [Lecture] {
        lectures
            .filter { $0.startMinutes == slot.start }
            .sorted { $0.displayTitle < $1.displayTitle }
    }

    /// A double period starting earlier still occupies this one.
    private var isCovered: Bool {
        lectures.contains { slot.overlaps(start: $0.startMinutes, end: $0.endMinutes) }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(slot.label)
                    .font(.caption.weight(.semibold))
                Text(slot.timeText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 78, alignment: .leading)

            if !starting.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(starting) { lecture in
                        lectureButton(lecture)
                    }
                }
            } else if isCovered {
                Text("devam ediyor")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Button(action: add) {
                    Label("Ekle", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private func lectureButton(_ lecture: Lecture) -> some View {
        Button {
            nav.show(lecture)
        } label: {
            HStack(spacing: 7) {
                if let course = lecture.course {
                    Circle()
                        .fill(Color(hex: course.colorHex))
                        .frame(width: 7, height: 7)
                }

                VStack(alignment: .leading, spacing: 0) {
                    if let course = lecture.course, lecture.hasTopic {
                        Text(course.name)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color(hex: course.colorHex))
                    }

                    Text(lecture.displayTitle)
                }

                FormatBadge(format: lecture.format)

                if spanLength(of: lecture) > 1 {
                    Text("\(spanLength(of: lecture)) ders")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.14), in: Capsule())
                }

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func spanLength(of lecture: Lecture) -> Int {
        LessonSlot.span(start: lecture.startMinutes, end: lecture.endMinutes).count
    }
}
