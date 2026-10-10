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
            // The URL is given explicitly on purpose: see `StoreLocation`.
            // Letting SwiftData pick the default put this archive in a file
            // another process also treats as its own, and it was emptied.
            try StoreLocation.prepare()

            modelContainer = try ModelContainer(
                for: Lecture.self,
                Course.self,
                Instructor.self,
                Committee.self,
                Tag.self,
                LectureFile.self,
                PastExam.self,
                configurations: ModelConfiguration(url: StoreLocation.storeURL)
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
                    .task { StoreBackup.write(from: modelContainer.mainContext) }
            } else {
                StoreFailureView(message: storeError ?? L.pick("Bilinmeyen hata", "Unknown error"))
            }
        }
        .defaultSize(width: 980, height: 660)
        .commands {
            // Dışa aktarma Dosya menüsünde, çünkü oraya bakılır. Panel ve
            // yazma işi `ArchiveExport`'ta: burada tutulacak bir durum yok,
            // o yüzden görünüm katmanına da ihtiyaç yok.
            CommandGroup(replacing: .appInfo) {
                Button(L.pick("MED Hakkında", "About MED")) {
                    AboutPanel.show()
                }
            }

            CommandGroup(replacing: .importExport) {
                Button(L.pick("JSON olarak dışa aktar…", "Export as JSON…")) {
                    if let modelContainer {
                        ArchiveExport.save(from: modelContainer.mainContext)
                    }
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(modelContainer == nil)
            }
        }

        Settings {
            SettingsView(storeURL: modelContainer?.configurations.first?.url)
                .environment(library)
        }
    }
}
