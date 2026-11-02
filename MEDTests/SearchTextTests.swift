import XCTest
@testable import MED

/// `SearchText.fold` is the comparison form the whole app leans on — matching,
/// deduping, the glossary's term/passage guards. Its Turkish handling is the
/// part a Unicode library would get wrong on its own, so it is pinned here.
final class SearchTextTests: XCTestCase {
    func testFoldsCaseAndWhitespace() {
        XCTAssertEqual(SearchText.fold("  Diffusion  "), "diffusion")
        XCTAssertEqual(SearchText.fold("GENOME"), "genome")
    }

    func testFoldsTurkishDottedAndDotlessI() {
        // The reason this helper exists: "BİYOFİZİK" and "Biyofizik" must match,
        // which plain Unicode folding does not manage for the dotless ı.
        XCTAssertEqual(SearchText.fold("BİYOFİZİK"), SearchText.fold("Biyofizik"))
        XCTAssertEqual(SearchText.fold("ışık"), "isik")
    }

    func testFoldsRemainingTurkishLetters() {
        XCTAssertEqual(SearchText.fold("Çğşöü"), "cgsou")
    }

    func testSameNameIgnoresCaseAndDiacritics() {
        XCTAssertTrue(SearchText.sameName("Vitamin D", "vitamin d"))
        XCTAssertFalse(SearchText.sameName("Insulin", "Insuline"))
    }
}
