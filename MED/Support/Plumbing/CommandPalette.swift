import Foundation
import SwiftData

/// One row of the ⌘K command palette: a thing you can jump to or do, with the
/// closure that does it. Built fresh each time the palette opens, so the
/// closures capture the live `nav` and context — nothing here is stored.
struct CommandAction: Identifiable {
    let id = UUID()
    let title: String
    /// A short grey hint on the right (what kind of thing this is). Optional.
    let subtitle: String?
    let symbolName: String
    /// What running the row does. The palette closes itself afterwards.
    let run: () -> Void
}

/// The command palette's catalogue and its matcher.
///
/// Phase 1 is deliberately small: jump to any sidebar section, plus the handful
/// of app-wide actions that already exist as menu items. Record search
/// (lectures, courses, people) is phase 2 and will append to this list.
enum CommandPalette {
    /// Builds the full action list for an open palette.
    ///
    /// - Parameters:
    ///   - nav: the window's navigation, captured by the section jumps.
    ///   - exportJSON: the Dosya‣JSON dışa aktar action, passed in because it
    ///     needs the model context, which lives in the view, not here. `nil`
    ///     when the store failed to open.
    static func actions(
        nav: AppNavigation,
        context: ModelContext?,
        exportJSON: (() -> Void)?
    ) -> [CommandAction] {
        var result: [CommandAction] = []

        // Jump to each sidebar section. Leaves any open slide reader so the
        // section you asked for is actually what you land on.
        for section in SidebarSection.allCases {
            result.append(CommandAction(
                title: L.pick("Git: ", "Go to ") + section.title,
                subtitle: L.pick("Bölüm", "Section"),
                symbolName: section.symbolName,
                run: {
                    nav.section = section
                    nav.readingSlide = nil
                    nav.fullScreenSlide = nil
                }
            ))
        }

        if let exportJSON {
            result.append(CommandAction(
                title: L.pick("JSON olarak dışa aktar…", "Export as JSON…"),
                subtitle: L.pick("Eylem", "Action"),
                symbolName: "square.and.arrow.up",
                run: exportJSON
            ))
        }

        if let context {
            result.append(contentsOf: recordActions(nav: nav, context: context))
        }

        return result
    }

    /// Jump-to-record rows for every lecture topic, course, academic, committee
    /// and tag in the store. Each one selects its record and switches the
    /// sidebar to the right section — the same hand-off the related screens use.
    ///
    /// Fetching happens here, each time the palette opens; for a single
    /// student's archive the counts are small, so a plain fetch is cheaper than
    /// keeping a live index around for a momentary overlay.
    private static func recordActions(nav: AppNavigation, context: ModelContext) -> [CommandAction] {
        var result: [CommandAction] = []

        // Lectures: deduplicated by topic. A topic can span several sessions
        // that share a title, and ten identical "Kalp kası" rows would just be
        // noise — one row that jumps to the topic is what you want.
        let lectures = (try? context.fetch(FetchDescriptor<Lecture>())) ?? []
        var seenTopics = Set<String>()
        for lecture in lectures {
            let name = lecture.displayTitle
            let key = SearchText.fold(name)
            guard !key.isEmpty, seenTopics.insert(key).inserted else { continue }
            result.append(CommandAction(
                title: name,
                subtitle: L.topic,
                symbolName: SidebarSection.lectures.symbolName,
                run: { nav.show(lecture) }
            ))
        }

        let courses = (try? context.fetch(FetchDescriptor<Course>())) ?? []
        for course in courses where !course.name.isEmpty {
            result.append(CommandAction(
                title: course.name,
                subtitle: L.course,
                symbolName: SidebarSection.courses.symbolName,
                run: {
                    nav.section = .courses
                    nav.courseID = course.persistentModelID
                }
            ))
        }

        let instructors = (try? context.fetch(FetchDescriptor<Instructor>())) ?? []
        for instructor in instructors where !instructor.name.isEmpty {
            result.append(CommandAction(
                title: instructor.displayName,
                subtitle: L.instructor,
                symbolName: SidebarSection.instructors.symbolName,
                run: {
                    nav.section = .instructors
                    nav.instructorID = instructor.persistentModelID
                }
            ))
        }

        let committees = (try? context.fetch(FetchDescriptor<Committee>())) ?? []
        for committee in committees {
            let label = committee.fullLabel
            guard !label.isEmpty else { continue }
            result.append(CommandAction(
                title: label,
                subtitle: L.committee,
                symbolName: SidebarSection.committees.symbolName,
                run: {
                    nav.section = .committees
                    nav.committeeID = committee.persistentModelID
                }
            ))
        }

        let tags = (try? context.fetch(FetchDescriptor<Tag>())) ?? []
        for tag in tags where !tag.name.isEmpty {
            result.append(CommandAction(
                title: tag.name,
                subtitle: L.tag,
                symbolName: SidebarSection.tags.symbolName,
                run: {
                    nav.section = .tags
                    nav.tagID = tag.persistentModelID
                }
            ))
        }

        return result
    }

    /// The actions whose title or subtitle match `query`, Turkish-folded through
    /// `SearchText`. An empty query returns everything, in catalogue order.
    static func filter(_ actions: [CommandAction], query: String) -> [CommandAction] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return actions }
        return actions.filter {
            SearchText.contains($0.title, query: trimmed)
                || SearchText.contains($0.subtitle ?? "", query: trimmed)
        }
    }
}
