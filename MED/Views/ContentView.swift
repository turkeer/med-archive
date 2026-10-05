import SwiftUI
import SwiftData

/// Two columns for now: the lecture list and the selected lecture.
///
/// The permanent sidebar from the design (Takvim / Dersler / Akademisyenler /
/// Komiteler / Etiketler) becomes a third, leading column in stage 3, once
/// there are screens to put behind those headings.
struct ContentView: View {
    @State private var selectedLectureID: PersistentIdentifier?

    var body: some View {
        NavigationSplitView {
            LectureListView(selection: $selectedLectureID)
                .navigationSplitViewColumnWidth(min: 280, ideal: 340)
        } detail: {
            LectureDetailColumn(lectureID: selectedLectureID)
        }
    }
}

/// Resolves the selected id to a lecture, and survives that lecture being
/// deleted: the lookup simply stops finding it and the placeholder returns.
private struct LectureDetailColumn: View {
    let lectureID: PersistentIdentifier?

    @Query private var lectures: [Lecture]

    var body: some View {
        if let lecture = lectures.first(where: { $0.persistentModelID == lectureID }) {
            LectureDetailView(lecture: lecture)
        } else {
            ContentUnavailableView(
                "Ders seçilmedi",
                systemImage: "sidebar.left",
                description: Text("Soldaki listeden bir ders seç.")
            )
        }
    }
}
