import SwiftUI
import SwiftData

@main
struct MEDApp: App {
    /// `nil` when the store could not be opened.
    ///
    /// This used to be a `fatalError`, which was a mistake: a failed schema
    /// migration killed the app before any window appeared, so all you saw was
    /// a Dock icon and nothing else, with the reason buried in the console.
    /// Now the failure gets a window that says what happened.
    private let modelContainer: ModelContainer?
    private let storeError: String?

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
            storeError = nil
        } catch {
            modelContainer = nil
            storeError = String(describing: error)
        }
    }

    var body: some Scene {
        WindowGroup {
            if let modelContainer {
                ContentView()
                    .environment(library)
                    .modelContainer(modelContainer)
            } else {
                StoreFailureView(message: storeError ?? "Bilinmeyen hata")
            }
        }
        .defaultSize(width: 980, height: 660)

        Settings {
            SettingsView()
                .environment(library)
        }
    }
}
