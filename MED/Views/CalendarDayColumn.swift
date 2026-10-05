import SwiftData
import SwiftUI

/// The selected day, laid out as the school's periods. Empty periods offer to
/// fill themselves; a lecture row hands you off to that lecture on the Konular
/// screen, the same way the related screens do.
///
/// Rows are runs, not periods. A lecture covering two periods gets one row
/// labelled "2.–3. ders" with its details written once, rather than a row that
/// says it and a second that only says "continues" — the same reasoning as the
/// merged blocks in the week grid, and the same `DayTimetable` behind both.
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
            SelectionPlaceholder(text: L.pick("Takvimden bir gün seç.", "Pick a day from the calendar."))
        }
    }

    private func content(for day: Date) -> some View {
        // Computed once for the day rather than once per row.
        let parts = LectureGrouping.partNumbers(for: dayLectures(on: day))

        return Form {
            if calendar.isDateInWeekend(day) {
                LectureLinkList(lectures: dayLectures(on: day), dayMode: true)
            } else {
                Section(L.pick("Ders saatleri", "Lesson times")) {
                    ForEach(DayTimetable.segments(for: timetabled(on: day))) { segment in
                        SegmentRow(segment: segment, parts: parts) {
                            newLectureRequest = NewLectureRequest(day: day, slot: segment.slot)
                        }
                    }
                }

                // Seminars, exams, anything that does not sit on a period.
                if !offTimetable(on: day).isEmpty {
                    LectureLinkList(
                        lectures: offTimetable(on: day),
                        title: L.pick("Program dışı", "Outside hours"),
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
                    newLectureRequest = NewLectureRequest(day: day, slot: nil)
                } label: {
                    Label(L.pick("Bu güne oturum ekle", "Add a session to this day"), systemImage: "plus")
                }
            }
        }
        .sheet(item: $newLectureRequest) { request in
            NewLectureSheet(initialDate: request.day, initialSlot: request.slot)
        }
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

/// One run of periods: what is in it, or an invitation to put something there.
private struct SegmentRow: View {
    let segment: DaySegment
    let parts: [PersistentIdentifier: (index: Int, total: Int)]
    let add: () -> Void

    @Environment(AppNavigation.self) private var nav

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Centred, so a run of two periods reads as one row with its
            // label beside the middle of it.
            VStack(alignment: .leading, spacing: 1) {
                Text(segment.label)
                    .font(.caption.weight(.semibold))
                Text(segment.timeText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 96, alignment: .leading)

            if segment.isFree {
                Button(action: add) {
                    Label(L.add, systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(segment.lectures) { lecture in
                        lectureButton(lecture)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, segment.span > 1 ? 8 : 2)
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

                    Text(titleText(for: lecture))
                }

                FormatBadge(format: lecture.format)

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Parts of one topic say which part they are. A lecture that merely
    /// spans several periods does not — the row label already says so.
    private func titleText(for lecture: Lecture) -> String {
        guard let part = parts[lecture.persistentModelID], lecture.hasTopic else {
            return lecture.displayTitle
        }
        return "\(lecture.displayTitle) (\(part.index))"
    }
}
