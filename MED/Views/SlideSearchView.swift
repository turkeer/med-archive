import SwiftData
import SwiftUI

/// How the slide hits are ordered.
enum SlideSearchSort: String, CaseIterable, Identifiable {
    /// The order the lessons were given in. The default, because the question
    /// this screen was built for is "where do I start", and a subject is
    /// taught from its foundations up: the earliest deck is the one that
    /// assumes the least.
    case taught

    /// Where the words appear most. What you want when you are after one
    /// particular fact rather than a way into the subject.
    case relevance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .taught:    return L.pick("Ders sırası", "Teaching order")
        case .relevance: return L.pick("En çok eşleşen", "Most matches")
        }
    }
}

/// Searching inside the slides themselves.
///
/// The Konular screen's search box reaches slide text too, but it answers with
/// *lectures*. This screen answers with pages: which deck, which page, and the
/// line the words sit in — because that is what you need when you remember a
/// term and not where you met it.
struct SlideSearchView: View {
    @Binding var query: String
    @Binding var selection: SlidePageSelection?

    @Environment(SlideIndex.self) private var slideIndex

    /// Files, to put a lecture's name on a hit. Every PDF under the root is
    /// indexed, including ones not attached to anything, so this is a lookup
    /// and not a filter.
    @Query private var files: [LectureFile]

    @AppStorage("slideSearchSort") private var sort: SlideSearchSort = .taught

    /// Held rather than computed in `body`.
    ///
    /// A computed property is read once per place it appears — here that was
    /// three times per redraw, so every keystroke ran the search three times.
    /// Held in state and refreshed once per question, it runs once.
    @State private var results: [Result] = []

    /// A file's hits, with whatever the archive knows about the file.
    /// Plain values, deliberately.
    ///
    /// These are held in state between searches, and a `Lecture` held across
    /// updates can be deleted under us — a dangling model object is a crash
    /// waiting for the wrong moment. What the list draws is copied out when
    /// the search runs.
    private struct Result: Identifiable {
        let hit: SlideIndex.FileHit
        let fileName: String

        let topic: String?
        let courseName: String?
        let courseColorHex: String?
        let date: Date?

        var id: String { hit.path }
    }

    /// What the results depend on. The index is in it because a search run
    /// while the slides were still being read has to be answered again once
    /// they are.
    private struct Question: Equatable {
        let query: String
        let sort: SlideSearchSort
        let indexed: Date?
    }

    var body: some View {
        List(selection: $selection) {
            if results.isEmpty {
                emptyState
            } else {
                summary

                ForEach(results) { result in
                    Section {
                        ForEach(result.hit.pages) { page in
                            row(page, in: result)
                        }

                        if result.hit.totalPages > result.hit.pages.count {
                            Text(L.pick(
                                "+ \(result.hit.totalPages - result.hit.pages.count) sayfa daha",
                                "+ \(result.hit.totalPages - result.hit.pages.count) more pages"
                            ))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        header(for: result)
                    }
                }
            }
        }
        .searchable(text: $query, prompt: L.pick("Slaytların içinde ara", "Search inside the slides"))
        .task(id: Question(query: query, sort: sort, indexed: slideIndex.lastBuilt)) {
            results = find()
        }
        .navigationTitle(L.pick("Slaytlarda ara", "Search slides"))
        .toolbar {
            ToolbarItem {
                Menu {
                    ForEach(SlideSearchSort.allCases) { option in
                        Button {
                            sort = option
                        } label: {
                            if option == sort {
                                Label(option.title, systemImage: "checkmark")
                            } else {
                                Text(option.title)
                            }
                        }
                    }
                } label: {
                    Label(sort.title, systemImage: "arrow.up.arrow.down")
                }
                .help(L.sort)
            }
        }
    }

    // MARK: Rows

    private var summary: some View {
        let pages = results.reduce(0) { $0 + $1.hit.pages.count }

        return Text(L.pick(
            "\(results.count) slaytta \(pages) sayfa",
            "\(pages) pages in \(results.count) decks"
        ))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func header(for result: Result) -> some View {
        HStack(spacing: 6) {
            if let topic = result.topic {
                Text(topic)

                if let name = result.courseName, let hex = result.courseColorHex {
                    Text(name)
                        .foregroundStyle(Color(hex: hex))
                }

                if let date = result.date {
                    Text(date.formatted(.dateTime.day().month(.abbreviated)))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(result.fileName)

                // Still worth showing: a slide you have not filed yet is
                // exactly the one you cannot find any other way, and seeing
                // it here is how you learn it needs attaching.
                Text(L.pick("derse bağlı değil", "not attached to a lesson"))
                    .foregroundStyle(.orange)
            }
        }
    }

    private func row(_ page: SlideIndex.PageHit, in result: Result) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(L.pick("s.\(page.number)", "p.\(page.number)"))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)

                if page.isRecognised {
                    // OCR can misread, so a hit from it is flagged rather
                    // than passed off as something the file itself said.
                    Text(L.pick("görüntüden okundu", "read from the image"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.14), in: Capsule())
                }
            }

            // Asked for here rather than carried in the result: the list is
            // lazy, so only the rows actually on screen pay for their line.
            Text(slideIndex.snippet(path: result.hit.path, page: page.number, query: query))
                .font(.callout)
                .lineLimit(3)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 2)
        .tag(SlidePageSelection(path: result.hit.path, page: page.number, query: query))
    }

    @ViewBuilder
    private var emptyState: some View {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).count < SlideIndex.minimumQuery {
            Text(L.pick(
                "Bir terim yaz. Arama slaytların içinde geçer; ders başlığında olması gerekmez.",
                "Type a term. This searches what the slides say, not what the lessons are called."
            ))
                .foregroundStyle(.secondary)
        } else if slideIndex.isWorking {
            Text(L.pick("Slaytlar hâlâ okunuyor, birazdan tekrar dene.", "The slides are still being read; try again in a moment."))
                .foregroundStyle(.secondary)
        } else {
            Text(L.pick("“\(query)” hiçbir slaytta geçmiyor.", "“\(query)” does not appear in any slide."))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Data

    private func find() -> [Result] {
        let lectures = Dictionary(
            files.compactMap { file -> (String, Lecture)? in
                guard let lecture = file.lecture else { return nil }
                return (file.relativePath, lecture)
            },
            uniquingKeysWith: { first, _ in first }
        )

        let found = slideIndex.search(query).map { hit -> Result in
            let lecture = lectures[hit.path]

            return Result(
                hit: hit,
                fileName: (hit.path as NSString).lastPathComponent,
                topic: lecture?.displayTitle,
                courseName: lecture?.course?.name,
                courseColorHex: lecture?.course?.colorHex,
                date: lecture?.date
            )
        }

        switch sort {
        case .taught:
            // Unattached files have no lesson and so no place in the teaching
            // order; they go last rather than being given a date they do not
            // have.
            return found.sorted { left, right in
                switch (left.date, right.date) {
                case let (lhs?, rhs?): return lhs == rhs ? left.fileName < right.fileName : lhs < rhs
                case (nil, _?):        return false
                case (_?, nil):        return true
                default:               return left.fileName < right.fileName
                }
            }

        case .relevance:
            return found.sorted { left, right in
                left.hit.pages.count == right.hit.pages.count
                    ? left.fileName < right.fileName
                    : left.hit.pages.count > right.hit.pages.count
            }
        }
    }
}
