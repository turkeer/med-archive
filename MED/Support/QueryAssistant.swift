import Foundation
import Observation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Turns a question into search terms, using the language model built into
/// the system.
///
/// The one job given to a model, deliberately. It does not answer the
/// question, summarise a slide or say what a topic means: this is an on-device
/// model of a few billion parameters, it will be confidently wrong about
/// medicine, and a student revising cannot tell which sentence was the wrong
/// one. Writing a search query is different — the result is immediately
/// visible, lands in the search box where it can be edited, and is checked by
/// whether it finds the right slides.
///
/// **It may only choose words the slides already use.** Asked to invent
/// keywords, this model was wrong about a third of the time and confidently
/// so: "tampon sistemleri" came back as "absorbent systems", "aksiyon
/// potansiyeli" as "proprioceptive sensibility". Handed the archive's own
/// vocabulary and told to choose from it, the same questions came back as
/// "buffer, systems" and "membrane, electrical, cells". Anything it returns
/// that is not in that vocabulary is dropped, so inventing a term is not
/// merely discouraged but impossible.
///
/// Everything here is optional. The framework exists from macOS 26 and needs
/// Apple Intelligence switched on, so on anything else `isAvailable` is false,
/// no button appears, and the rest of searching is untouched.
@MainActor
@Observable
final class QueryAssistant {
    private(set) var isWorking = false

    /// Set when a translation failed, for the screen to say so once.
    private(set) var failure: String?

    var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    /// Search terms for `question`, comma separated, or `nil` when the model
    /// is unavailable or gave nothing usable.
    ///
    /// Comma separated because that is what the search box means by "any of
    /// these" — the answer goes in the box as text, not into a hidden query.
    func terms(for question: String, vocabulary: SlideIndex.Vocabulary) async -> String? {
        let asked = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !asked.isEmpty, isAvailable, !vocabulary.isEmpty else { return nil }

        isWorking = true
        failure = nil
        defer { isWorking = false }

        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            do {
                let session = LanguageModelSession(instructions: Self.instructions(for: vocabulary))
                let answer = try await session.respond(to: asked)
                let cleaned = Self.clean(answer.content, allowed: vocabulary.allowed)

                if cleaned.isEmpty {
                    failure = L.pick(
                        "Bu soruya karşılık gelen bir terim slaytlarda bulunamadı.",
                        "No term for this question could be found in the slides."
                    )
                    return nil
                }

                return cleaned
            } catch {
                failure = L.pick("Çeviri başarısız oldu.", "The translation failed.")
                return nil
            }
        }
        #endif

        return nil
    }

    private static func instructions(for vocabulary: SlideIndex.Vocabulary) -> String {
        """
        A medical student asks a question, usually in Turkish. You pick the \
        words that will find it in an index of their lecture slides.

        You may only use words from this list, which is the vocabulary of \
        those slides:

        \(vocabulary.terms.joined(separator: ", "))

        Reply with the four to eight words from the list that best match the \
        question, comma separated, and nothing else: no numbering, no \
        explanation, no sentences. If the question matches nothing in the \
        list, reply with the single word NONE.
        """
    }

    /// Keeps the terms that are really in the archive and throws away
    /// everything else the model said.
    ///
    /// Two things are being guarded against. Models asked for bare keywords
    /// sometimes answer with a sentence, a preamble or a numbered list
    /// anyway. And this one, even when handed a list to choose from, slips in
    /// a word that is not on it — "potassium" when the list had no such
    /// entry. Checking against the vocabulary turns both into nothing.
    static func clean(_ answer: String, allowed: Set<String>) -> String {
        let firstBlock = answer
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first { $0.contains(",") } ?? answer[...].split(separator: "\n").first ?? ""

        let terms = firstBlock
            .split(separator: ",")
            .map { term -> String in
                term
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    // Numbering, bullets and quotes the instructions asked it
                    // not to use.
                    .trimmingCharacters(in: CharacterSet(charactersIn: "0123456789.)-–—*•\"'“”`[]"))
                    .trimmingCharacters(in: .whitespaces)
            }
            .filter { term in
                term.count >= SlideIndex.minimumQuery
                    && term.count <= 40
                    && allowed.contains(SearchText.fold(term))
            }
            .prefix(8)

        // Duplicates come back often enough to be worth dropping; order is
        // kept, because the model puts its best guess first.
        var seen: Set<String> = []
        return terms
            .filter { seen.insert(SearchText.fold($0)).inserted }
            .joined(separator: ", ")
    }
}
