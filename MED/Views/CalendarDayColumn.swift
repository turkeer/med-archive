import SwiftUI
import SwiftData

/// The selected day's lectures. Clicking one hands you off to it on the
/// Konular screen, the same way the related screens do.
struct CalendarDayColumn: View {
    let day: Date?

    @Query private var lectures: [Lecture]

    @State private var isAddingLecture = false
    @State private var newLectureSeed = UUID()

    private let calendar = Calendar.current

    var body: some View {
        if let day {
            Form {
                LectureLinkList(
                    lectures: dayLectures(on: day),
                    title: "Oturumlar",
                    dayMode: true
                )
            }
            .formStyle(.grouped)
            .navigationTitle(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
            .navigationSubtitle(day.formatted(.dateTime.year()))
            .toolbar {
                ToolbarItem {
                    Button {
                        newLectureSeed = UUID()
                        isAddingLecture = true
                    } label: {
                        Label("Bu güne oturum ekle", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isAddingLecture) {
                NewLectureSheet(initialDate: day)
                    .id(newLectureSeed)
            }
        } else {
            SelectionPlaceholder(text: "Takvimden bir gün seç.")
        }
    }

    private func dayLectures(on day: Date) -> [Lecture] {
        let target = calendar.startOfDay(for: day)
        return lectures.filter { calendar.startOfDay(for: $0.date) == target }
    }
}
