import SwiftUI
import SwiftData

@main
struct MEDApp: App {
    private let modelContainer: ModelContainer

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
        }
        .modelContainer(modelContainer)
        .defaultSize(width: 900, height: 620)
    }
}
