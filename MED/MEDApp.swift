import SwiftUI
import SwiftData

@main
struct MEDApp: App {
    private let modelContainer: ModelContainer

    @State private var library = LibraryRoot()

    init() {
        do {
            modelContainer = try ModelContainer(
                for: Lecture.self,
                Course.self,
                Instructor.self,
                Committee.self,
                Tag.self,
                LectureFile.self
            )
        } catch {
            // Nothing sensible to fall back to: without a store there is no app.
            fatalError("MED veritabanı açılamadı: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(library)
        }
        .modelContainer(modelContainer)
        .defaultSize(width: 980, height: 660)

        Settings {
            SettingsView()
                .environment(library)
        }
    }
}
