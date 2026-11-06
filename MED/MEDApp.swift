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
    @State private var slideIndex = SlideIndex()
    @State private var queryAssistant = QueryAssistant()
    @State private var glossaryModel = GlossaryModel()
    @State private var referenceLibrary = ReferenceLibrary()

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
                    .environment(slideIndex)
                    .environment(queryAssistant)
                    .environment(glossaryModel)
                    .environment(referenceLibrary)
                    .modelContainer(modelContainer)
                    .task {
                        // iOS: fihristlemeden önce öksüz (kayda bağlı olmayan)
                        // konteyner dosyalarını temizle, yoksa silinen derslerin
                        // dosyaları sözlükte/aramada görünmeye devam eder.
                        #if os(iOS)
                        ContainerCleanup.removeOrphans(context: modelContainer.mainContext, library: library)
                        #endif
                        slideIndex.refresh(root: library.url)
                    }
                    .onChange(of: library.url) { _, root in
                        slideIndex.refresh(root: root)
                    }
                    .task { await StoreBackup.keepWriting(from: modelContainer.mainContext) }
                    .task { await StoreBackup.writeOnLeaving(from: modelContainer.mainContext) }
            } else {
                StoreFailureView(message: storeError ?? L.pick("Bilinmeyen hata", "Unknown error"))
            }
        }
        .defaultSize(width: 980, height: 660)
        .commands {
            // ⌘K — hızlı git. Pencerenin `nav`'ı burada doğrudan görünmez
            // (menüler pencerelerin üstündedir), o yüzden odaklı değer köprüsü
            // üzerinden erişilir.
            QuickOpenCommands()

            // Dışa aktarma Dosya menüsünde, çünkü oraya bakılır. Panel ve
            // yazma işi `ArchiveExport`'ta: burada tutulacak bir durum yok,
            // o yüzden görünüm katmanına da ihtiyaç yok.
            #if os(macOS)
            CommandGroup(replacing: .appInfo) {
                Button(L.pick("MED Hakkında", "About MED")) {
                    AboutPanel.show()
                }
            }
            #endif

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

        // `Settings` sahnesi yalnızca macOS'ta var (⌘,). iPad'de ayarlar
        // uygulama içi bir ekrandan gelecek (sonraki faz).
        #if os(macOS)
        Settings {
            SettingsView(storeURL: modelContainer?.configurations.first?.url)
                .environment(library)
                .environment(slideIndex)
                .environment(referenceLibrary)
        }
        #endif
    }
}

/// The ⌘K "hızlı git" menu command.
///
/// A `Commands` struct of its own because it needs `@FocusedValue`, which can
/// only live in a `View` or `Commands` type — not inline in `MEDApp.body`. It
/// reads the frontmost window's navigation, published by `ContentView` through
/// `.focusedSceneValue`, and flips the palette open. Disabled (and so greyed
/// out) when no window is focused.
struct QuickOpenCommands: Commands {
    @FocusedValue(\.appNavigation) private var nav

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button(L.pick("Hızlı git…", "Quick open…")) {
                nav?.commandPaletteOpen = true
            }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(nav == nil)
        }
    }
}
