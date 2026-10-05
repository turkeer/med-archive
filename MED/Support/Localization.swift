import Foundation
import Observation

/// The two languages the interface speaks.
enum AppLanguageChoice: String, CaseIterable, Identifiable {
    case turkish = "tr"
    case english = "en"

    var id: String { rawValue }

    /// Each named in itself, not in the current language: a language list you
    /// cannot read is no use when you are in the wrong language.
    var endonym: String {
        switch self {
        case .turkish: return "Türkçe"
        case .english: return "English"
        }
    }

    /// Drives `Date` and number formatting, so a month reads "Ekim" or
    /// "October" to match the rest of the window.
    var locale: Locale {
        switch self {
        case .turkish: return Locale(identifier: "tr_TR")
        case .english: return Locale(identifier: "en_US")
        }
    }

    /// Turkish when the Mac is Turkish, English otherwise.
    static var systemDefault: AppLanguageChoice {
        Locale.current.language.languageCode?.identifier == "tr" ? .turkish : .english
    }
}

/// Which language the interface is in, remembered across launches.
///
/// A shared object rather than an environment value, because the strings are
/// not only in views: a lecture's `displayTitle`, a slot's "3. ders", a sort
/// order's name all need the language too, and none of them can reach the
/// environment. `@Observable` still does the right thing for the views —
/// reading the language inside a `body` registers the dependency, so changing
/// it redraws everything that shows a word.
///
/// Changing it takes effect immediately. The usual macOS route, writing
/// `AppleLanguages` into the defaults, needs a relaunch — which is a strange
/// thing to ask of someone who has just picked a language from a menu.
@Observable
final class AppLanguage {
    static let shared = AppLanguage()

    private static let defaultsKey = "MEDLanguage"

    var choice: AppLanguageChoice {
        didSet {
            UserDefaults.standard.set(choice.rawValue, forKey: Self.defaultsKey)
        }
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? ""
        choice = AppLanguageChoice(rawValue: stored) ?? AppLanguageChoice.systemDefault
    }
}

/// The interface's words.
///
/// `L.pick("Konular", "Topics")` is written at the point of use, and only the
/// words that appear in several places get a name here. That is the opposite
/// of the usual key-and-table arrangement, on purpose:
///
/// - **Nothing can be left untranslated.** Both languages are arguments of the
///   same call, so a missing one is a compile error rather than a key that
///   falls through to its own name at runtime.
/// - **The two versions sit next to each other, in context.** A table makes
///   you read one language in one file and the other in another, and a name
///   like `scanWeakFooter` tells you less about the sentence than the sentence
///   does.
/// - No key can be misspelled, orphaned, or quietly used for two different
///   sentences that happen to match in Turkish.
enum L {
    /// Reading the language here is what ties every view that shows a word to
    /// the language setting: the access happens inside the view's `body`.
    static func pick(_ turkish: String, _ english: String) -> String {
        AppLanguage.shared.choice == .turkish ? turkish : english
    }

    static var locale: Locale {
        AppLanguage.shared.choice.locale
    }

    // MARK: Words that appear all over

    static var cancel: String { pick("Vazgeç", "Cancel") }
    static var save: String { pick("Kaydet", "Save") }
    static var add: String { pick("Ekle", "Add") }
    static var delete: String { pick("Sil", "Delete") }
    static var close: String { pick("Kapat", "Close") }
    static var apply: String { pick("Uygula", "Apply") }
    static var clear: String { pick("Temizle", "Clear") }
    static var remove: String { pick("Kaldır", "Remove") }
    static var search: String { pick("Ara", "Search") }
    static var sort: String { pick("Sıralama", "Sort") }
    static var all: String { pick("Hepsi", "All") }
    static var none: String { pick("Yok", "None") }
    static var name: String { pick("Ad", "Name") }
    static var color: String { pick("Renk", "Color") }
    static var format: String { pick("Tür", "Type") }
    static var notes: String { pick("Notlar", "Notes") }
    static var chooseFolder: String { pick("Klasör seç…", "Choose folder…") }
    static var addFile: String { pick("Dosya ekle", "Add file") }
    static var showInFinder: String { pick("Finder'da göster", "Show in Finder") }
    static var clearFilters: String { pick("Filtreleri temizle", "Clear filters") }
    static var missingFiles: String { pick("Dosyası olmayanlar", "Missing files") }

    // MARK: The things the archive is made of

    static var calendar: String { pick("Takvim", "Calendar") }
    static var topics: String { pick("Konular", "Topics") }
    static var courses: String { pick("Dersler", "Courses") }
    static var instructors: String { pick("Akademisyenler", "Instructors") }
    static var committees: String { pick("Komiteler", "Committees") }
    static var tags: String { pick("Etiketler", "Tags") }

    static var course: String { pick("Ders", "Course") }
    static var instructor: String { pick("Akademisyen", "Instructor") }
    static var committee: String { pick("Komite", "Committee") }
    static var tag: String { pick("Etiket", "Tag") }
    static var topic: String { pick("Konu", "Topic") }
    static var sessions: String { pick("Oturumlar", "Sessions") }
    static var files: String { pick("Dosyalar", "Files") }

    static var newCourse: String { pick("Yeni ders", "New course") }
    static var newInstructor: String { pick("Yeni akademisyen", "New instructor") }
    static var newCommittee: String { pick("Yeni komite", "New committee") }
    static var newTag: String { pick("Yeni etiket", "New tag") }
    static var newSession: String { pick("Yeni oturum", "New session") }

    // MARK: Counts and placeholders

    /// "4 oturum" / "4 sessions".
    static func sessionCount(_ count: Int) -> String {
        pick("\(count) oturum", count == 1 ? "1 session" : "\(count) sessions")
    }

    /// "2 ders" / "2 lessons" — the periods one topic took.
    static func lessonCount(_ count: Int) -> String {
        pick("\(count) ders", count == 1 ? "1 lesson" : "\(count) lessons")
    }

    static func fileCount(_ count: Int) -> String {
        pick("\(count) dosya", count == 1 ? "1 file" : "\(count) files")
    }

    /// "3. ders" / "Lesson 3".
    static func lesson(_ number: Int) -> String {
        pick("\(number). ders", "Lesson \(number)")
    }

    /// "2.–3. ders" / "Lessons 2–3".
    static func lessonRange(_ first: Int, _ last: Int) -> String {
        if first == last { return lesson(first) }
        return pick("\(first).–\(last). ders", "Lessons \(first)–\(last)")
    }

    /// "1., 7. ders" / "Lessons 1, 7" — periods that are not consecutive.
    static func lessonList(_ numbers: [Int]) -> String {
        let joined = numbers.map(String.init).joined(separator: ", ")
        return pick("\(joined). ders", "Lessons \(joined)")
    }

    static var noTime: String { pick("saat yok", "no time") }
    static var untitled: String { pick("(başlıksız)", "(untitled)") }
    static var unnamed: String { pick("(adsız)", "(unnamed)") }

    // MARK: Dates outside a view

    /// `Date.formatted` reads the process locale, not the window's, so a date
    /// built in a model or a helper has to be told which language it is in.
    static func format(_ date: Date, _ style: Date.FormatStyle) -> String {
        date.formatted(style.locale(locale))
    }
}
