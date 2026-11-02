import SwiftData
import XCTest
@testable import MED

/// The pure crossover computation: a term counts as a crossover only when it
/// appears in more than one *course* of the *same* committee. These assert the
/// grouping, the within-committee rule, de-duplication, and the known naive
/// matching (TR and EN spellings do not merge yet).
@MainActor
final class CommitteeIntersectionTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Lecture.self, Course.self, Instructor.self, Committee.self,
            Tag.self, LectureFile.self, PastExam.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
    }

    // MARK: Fixtures

    /// Inserts a lecture with one slide file, under the given course and
    /// committee, and returns its file path.
    @discardableResult
    private func lecture(title: String, course: Course, committee: Committee, path: String) -> String {
        let lecture = Lecture(title: title, course: course, committee: committee)
        context.insert(lecture)
        let file = LectureFile(fileName: (path as NSString).lastPathComponent,
                               relativePath: path, kind: .slide, lecture: lecture)
        context.insert(file)
        return path
    }

    private func lecturesByPath() -> [String: Lecture] {
        let files = (try? context.fetch(FetchDescriptor<LectureFile>())) ?? []
        return Dictionary(
            files.compactMap { file -> (String, Lecture)? in
                guard let lecture = file.lecture else { return nil }
                return (file.relativePath, lecture)
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func term(_ term: String, _ path: String, _ page: Int) -> GlossaryModel.CuratedTerm {
        GlossaryModel.CuratedTerm(term: term, path: path, page: page)
    }

    /// A stub for `SlideIndex.phraseLocations`: maps a folded phrase to the
    /// paths (and page) whose slide text "contains" it, so the tests drive the
    /// appears-elsewhere side without a real index.
    private func locator(_ map: [String: [String: Int]]) -> (String) -> [String: Int] {
        { phrase in map[SearchText.fold(phrase)] ?? [:] }
    }

    /// Nothing appears anywhere — only the defined side counts.
    private func noAppearances(_ phrase: String) -> [String: Int] { [:] }

    // MARK: Tests

    func testCrossoverAcrossTwoCoursesOfOneCommittee() throws {
        let komiteI = Committee(name: "Hücre Bilimleri", code: "Komite I")
        let anatomi = Course(name: "Anatomi")
        let histoloji = Course(name: "Histoloji")
        context.insert(komiteI); context.insert(anatomi); context.insert(histoloji)

        let anatPath = lecture(title: "Mide anatomisi", course: anatomi, committee: komiteI, path: "KomiteI/Anatomi/mide.pdf")
        let histoPath = lecture(title: "Mide histolojisi", course: histoloji, committee: komiteI, path: "KomiteI/Histoloji/mide.pdf")

        let terms = [
            term("Parietal hücre", anatPath, 3),
            term("Parietal hücre", histoPath, 5),
        ]

        let points = CommitteeIntersection.points(
            from: terms, lecturesByPath: lecturesByPath(), locate: noAppearances)

        XCTAssertEqual(points.count, 1)
        let point = try XCTUnwrap(points.first)
        XCTAssertEqual(SearchText.fold(point.term), SearchText.fold("Parietal hücre"))
        XCTAssertEqual(point.courseCount, 2)
        XCTAssertEqual(point.committeeLabel, "Komite I")
        XCTAssertEqual(point.occurrences.count, 2)
    }

    func testSingleCourseIsNotACrossover() {
        let komiteI = Committee(name: "Hücre", code: "Komite I")
        let anatomi = Course(name: "Anatomi")
        context.insert(komiteI); context.insert(anatomi)

        let p1 = lecture(title: "Ders 1", course: anatomi, committee: komiteI, path: "KomiteI/Anatomi/a.pdf")
        let p2 = lecture(title: "Ders 2", course: anatomi, committee: komiteI, path: "KomiteI/Anatomi/b.pdf")

        // Same term, same committee, but only one course → not a crossover,
        // and it is mentioned nowhere else.
        let terms = [term("Mukoza", p1, 1), term("Mukoza", p2, 2)]
        let points = CommitteeIntersection.points(
            from: terms, lecturesByPath: lecturesByPath(), locate: noAppearances)

        XCTAssertTrue(points.isEmpty)
    }

    func testSameTermInDifferentCommitteesIsNotACrossover() {
        let komiteI = Committee(name: "Bir", code: "Komite I")
        let komiteII = Committee(name: "İki", code: "Komite II")
        let anatomi = Course(name: "Anatomi")
        context.insert(komiteI); context.insert(komiteII); context.insert(anatomi)

        // Same course name, but one lecture in each committee. Neither committee
        // has two courses, so there is no within-committee crossover.
        let p1 = lecture(title: "A", course: anatomi, committee: komiteI, path: "KomiteI/Anatomi/a.pdf")
        let p2 = lecture(title: "B", course: anatomi, committee: komiteII, path: "KomiteII/Anatomi/b.pdf")

        // "Omurga" (≥6 chars) clears the generic filter, so this really tests
        // the committee rule rather than being dropped as a short word.
        let terms = [term("Omurga", p1, 1), term("Omurga", p2, 1)]
        let points = CommitteeIntersection.points(
            from: terms, lecturesByPath: lecturesByPath(), locate: noAppearances)

        XCTAssertTrue(points.isEmpty)
    }

    func testDuplicateOnSameSlideCountedOnce() throws {
        let komiteI = Committee(name: "Hücre", code: "Komite I")
        let anatomi = Course(name: "Anatomi")
        let histoloji = Course(name: "Histoloji")
        context.insert(komiteI); context.insert(anatomi); context.insert(histoloji)

        let anatPath = lecture(title: "A", course: anatomi, committee: komiteI, path: "KomiteI/Anatomi/a.pdf")
        let histoPath = lecture(title: "H", course: histoloji, committee: komiteI, path: "KomiteI/Histoloji/h.pdf")

        // The anatomy slide lists the term twice on the same page; it must not
        // inflate the occurrence count.
        let terms = [
            term("Epitel", anatPath, 2),
            term("Epitel", anatPath, 2),
            term("Epitel", histoPath, 4),
        ]
        let points = CommitteeIntersection.points(
            from: terms, lecturesByPath: lecturesByPath(), locate: noAppearances)

        let point = try XCTUnwrap(points.first)
        XCTAssertEqual(point.occurrences.count, 2)
        XCTAssertEqual(point.courseCount, 2)
    }

    func testStrongerCrossoverSortsFirst() throws {
        let komiteI = Committee(name: "Hücre", code: "Komite I")
        let anatomi = Course(name: "Anatomi")
        let histoloji = Course(name: "Histoloji")
        let biyokimya = Course(name: "Biyokimya")
        context.insert(komiteI); context.insert(anatomi)
        context.insert(histoloji); context.insert(biyokimya)

        let a = lecture(title: "A", course: anatomi, committee: komiteI, path: "KomiteI/Anatomi/a.pdf")
        let h = lecture(title: "H", course: histoloji, committee: komiteI, path: "KomiteI/Histoloji/h.pdf")
        let b = lecture(title: "B", course: biyokimya, committee: komiteI, path: "KomiteI/Biyokimya/b.pdf")

        // "Hücreler" spans three courses; "Dokular" spans two → the three-course
        // one is the stronger crossover and must sort first. (Both ≥6 chars so
        // the generic filter keeps them.)
        let terms = [
            term("Hücreler", a, 1), term("Hücreler", h, 1), term("Hücreler", b, 1),
            term("Dokular", a, 2), term("Dokular", h, 2),
        ]
        let points = CommitteeIntersection.points(
            from: terms, lecturesByPath: lecturesByPath(), locate: noAppearances)

        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points.first?.courseCount, 3)
        XCTAssertEqual(SearchText.fold(points.first?.term ?? ""), SearchText.fold("Hücreler"))
    }

    // MARK: Appears-elsewhere side

    func testMentionElsewherePromotesToCrossover() throws {
        let komiteI = Committee(name: "Hücre", code: "Komite I")
        let fizyoloji = Course(name: "Fizyoloji")
        let anatomi = Course(name: "Anatomi")
        context.insert(komiteI); context.insert(fizyoloji); context.insert(anatomi)

        // Defined only in Physiology…
        let fizyoPath = lecture(title: "Zar potansiyeli", course: fizyoloji, committee: komiteI, path: "KomiteI/Fizyoloji/zar.pdf")
        // …but Anatomy has a slide that mentions it.
        let anatPath = lecture(title: "Sinir", course: anatomi, committee: komiteI, path: "KomiteI/Anatomi/sinir.pdf")

        let terms = [term("Membrane potential", fizyoPath, 7)]
        let locate = locator(["membrane potential": [anatPath: 3]])

        let points = CommitteeIntersection.points(
            from: terms, lecturesByPath: lecturesByPath(), locate: locate)

        let point = try XCTUnwrap(points.first)
        XCTAssertEqual(point.courseCount, 2)
        XCTAssertEqual(point.occurrences.count, 2)
        XCTAssertEqual(point.occurrences.filter(\.isDefinition).count, 1)
        XCTAssertEqual(point.occurrences.filter { !$0.isDefinition }.count, 1)
    }

    func testMentionInSameCourseDoesNotCount() {
        let komiteI = Committee(name: "Hücre", code: "Komite I")
        let fizyoloji = Course(name: "Fizyoloji")
        context.insert(komiteI); context.insert(fizyoloji)

        let p1 = lecture(title: "A", course: fizyoloji, committee: komiteI, path: "KomiteI/Fizyoloji/a.pdf")
        let p2 = lecture(title: "B", course: fizyoloji, committee: komiteI, path: "KomiteI/Fizyoloji/b.pdf")

        // Defined in Physiology, mentioned again in Physiology → still one course.
        let terms = [term("Aksiyon potansiyeli", p1, 1)]
        let locate = locator(["aksiyon potansiyeli": [p2: 2]])

        let points = CommitteeIntersection.points(
            from: terms, lecturesByPath: lecturesByPath(), locate: locate)

        XCTAssertTrue(points.isEmpty)
    }

    // MARK: Noise filter

    func testGenericFilterDropsCommonWordsAndFragments() {
        XCTAssertTrue(CommitteeIntersection.isGeneric("type"))
        XCTAssertTrue(CommitteeIntersection.isGeneric("found in"))
        XCTAssertTrue(CommitteeIntersection.isGeneric("these are"))
        XCTAssertTrue(CommitteeIntersection.isGeneric("three types"))
        XCTAssertTrue(CommitteeIntersection.isGeneric("ion"))        // too short
    }

    func testGenericFilterKeepsRealConcepts() {
        XCTAssertFalse(CommitteeIntersection.isGeneric("membrane potential"))
        XCTAssertFalse(CommitteeIntersection.isGeneric("cytoskeleton"))
        XCTAssertFalse(CommitteeIntersection.isGeneric("amino acids"))
        XCTAssertFalse(CommitteeIntersection.isGeneric("bone marrow"))
    }
}
