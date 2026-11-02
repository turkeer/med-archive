import Foundation
import SwiftData

/// Disiplinler-arası kesişim noktaları: bir komitede, **birden fazla farklı
/// derse** yayılan bir kavram.
///
/// Tıp 1'in en büyük sıkıntısı komitelerin silolu olmasıdır — midenin
/// anatomisini bir gün, histolojisini başka bir gün, biyokimyasını daha başka
/// bir gün görürsün ve beyninde üç ayrı çekmecede kalır. Bu hesap o çekmeceleri
/// birleştirir: sözlüğün bir derste **tanımladığı** bir terimi alır ve aynı
/// komitenin öbür derslerinin slaytlarında da **geçip geçmediğine** bakar.
///
/// Neden "iki derste de tanımlı" değil de "birinde tanımlı, ötekinde geçiyor"?
/// Çünkü gerçek veride bir terim nadiren iki ayrı derste birebir aynı sözcükle
/// *tanımlanır* — ama bir derste öğrenilen kavram, başka bir dersin slaytlarında
/// sık sık *geçer*. Kesişimi yaratan da budur. Bedeli gürültüdür ("transport",
/// "type" gibi genel kelimeler her yerde geçer), o yüzden genel/parça terimler
/// `isGeneric` ile elenir.
///
/// Tamamen türetilmiş, saf bir hesap: hiçbir model, ağ veya yeni veri yok.
enum CommitteeIntersection {

    /// Bir terimin tek bir derste görünüşü — tıklanıp gidilebilen bir slayt.
    struct Occurrence: Identifiable {
        let id: String
        let courseName: String
        let courseColorHex: String?
        let lectureTitle: String
        let path: String
        let page: Int
        /// Slayda giderken vurgulamak için terim.
        let term: String
        /// Bu ders terimi *tanımlıyor* mu (sözlük), yoksa yalnızca *geçiyor* mu.
        let isDefinition: Bool
    }

    /// Bir komitede, birden fazla derse yayılan tek bir terim.
    struct Point: Identifiable {
        let id: String
        let term: String
        let committeeName: String
        let committeeLabel: String
        let committeeColorHex: String
        /// Kaç farklı derse yayıldığı — kesişimin "gücü".
        let courseCount: Int
        /// Her ders için bir görünüş; ders adına göre sıralı.
        let occurrences: [Occurrence]
    }

    /// Kesişim noktalarını hesaplar.
    ///
    /// - Parameters:
    ///   - terms: küratörlü sözlük terimleri (`GlossaryModel.curatedTerms`).
    ///   - lecturesByPath: slayt yolunu dersine bağlayan harita.
    ///   - locate: bir terimin geçtiği yerleri veren kapanış (yol → ilk sayfa);
    ///     uygulamada `SlideIndex.phraseLocations`, testte sahte bir sözlük.
    ///
    /// SwiftData modellerine dokunduğu ve `GlossaryModel.normalizeTerm` çağırdığı
    /// için ana aktörde çalışır — zaten çağıran da ekrandır.
    @MainActor
    static func points(
        from terms: [GlossaryModel.CuratedTerm],
        lecturesByPath: [String: Lecture],
        locate: (String) -> [String: Int]
    ) -> [Point] {

        struct Agg {
            var displayTerm: String
            var rawTerm: String
            var committee: Committee
            var definedByKey: [String: Occurrence]
            var definedCourseIDs: Set<PersistentIdentifier>
        }
        struct Key: Hashable {
            let committee: PersistentIdentifier
            let term: String
        }

        // 1) Sözlüğün tanımladığı terimleri komite + folded-terim bazında topla.
        var aggs: [Key: Agg] = [:]
        for item in terms {
            let folded = SearchText.fold(item.term)
            guard folded.count >= 3, !isGeneric(folded) else { continue }

            guard let lecture = lecturesByPath[item.path],
                  let committee = lecture.committee,
                  let course = lecture.course
            else { continue }

            let key = Key(committee: committee.persistentModelID, term: folded)
            let occKey = "def#\(item.path)#\(item.page)"
            let occurrence = Occurrence(
                id: occKey,
                courseName: course.name,
                courseColorHex: course.colorHex,
                lectureTitle: lecture.displayTitle,
                path: item.path,
                page: item.page,
                term: item.term,
                isDefinition: true
            )

            if aggs[key] != nil {
                aggs[key]!.definedByKey[occKey] = occurrence
                aggs[key]!.definedCourseIDs.insert(course.persistentModelID)
            } else {
                aggs[key] = Agg(
                    displayTerm: GlossaryModel.normalizeTerm(item.term),
                    rawTerm: item.term,
                    committee: committee,
                    definedByKey: [occKey: occurrence],
                    definedCourseIDs: [course.persistentModelID]
                )
            }
        }

        // 2) Her terim için, aynı komitenin BAŞKA derslerinde geçtiği yerleri bul.
        var points: [Point] = []
        for (key, agg) in aggs {
            let committeeID = agg.committee.persistentModelID

            var appearsByCourse: [PersistentIdentifier: Occurrence] = [:]
            for (path, page) in locate(agg.rawTerm) {
                guard let lecture = lecturesByPath[path],
                      let committee = lecture.committee,
                      committee.persistentModelID == committeeID,
                      let course = lecture.course
                else { continue }

                let courseID = course.persistentModelID
                // Zaten tanımlayan ders; ikinci kez saymayalım.
                if agg.definedCourseIDs.contains(courseID) { continue }
                // Ders başına tek görünüş yeter.
                if appearsByCourse[courseID] != nil { continue }

                appearsByCourse[courseID] = Occurrence(
                    id: "seen#\(path)#\(page)",
                    courseName: course.name,
                    courseColorHex: course.colorHex,
                    lectureTitle: lecture.displayTitle,
                    path: path,
                    page: page,
                    term: agg.rawTerm,
                    isDefinition: false
                )
            }

            let courseCount = agg.definedCourseIDs.union(appearsByCourse.keys).count
            guard courseCount >= 2 else { continue }

            let occurrences = (Array(agg.definedByKey.values) + Array(appearsByCourse.values))
                .sorted {
                    if $0.courseName != $1.courseName {
                        return $0.courseName.localizedStandardCompare($1.courseName) == .orderedAscending
                    }
                    if $0.path != $1.path { return $0.path < $1.path }
                    return $0.page < $1.page
                }

            points.append(Point(
                id: "\(agg.committee.shortLabel)|\(agg.committee.name)|\(key.term)",
                term: agg.displayTerm,
                committeeName: agg.committee.name,
                committeeLabel: agg.committee.shortLabel,
                committeeColorHex: agg.committee.colorHex,
                courseCount: courseCount,
                occurrences: occurrences
            ))
        }

        // Önce en çok derse yayılan (en değerli) kesişimler, sonra alfabetik.
        return points.sorted {
            if $0.courseCount != $1.courseCount { return $0.courseCount > $1.courseCount }
            return $0.term.localizedStandardCompare($1.term) == .orderedAscending
        }
    }

    // MARK: Gürültü filtresi

    /// Her derste geçen, kavram taşımayan genel kelimeler. Foldlanmış hâlleri.
    private static let genericWords: Set<String> = [
        "include", "includes", "including", "type", "types", "way", "ways",
        "base", "bases", "found", "component", "components", "material",
        "materials", "solution", "solutions", "weight", "reaction", "reactions",
        "form", "forms", "group", "groups", "system", "systems", "part", "parts",
        "process", "processes", "function", "functions", "structure",
        "structures", "example", "examples", "number", "numbers", "level",
        "levels", "region", "regions", "area", "areas", "factor", "factors",
        "effect", "effects", "result", "results", "value", "values", "property",
        "properties", "feature", "features", "method", "methods", "step",
        "steps", "state", "states", "point", "points", "case", "cases",
        "amount", "amounts", "rate", "rates", "size", "sizes", "range", "ranges",
        "change", "changes", "role", "roles", "unit", "units", "set", "sets",
        "line", "lines", "field", "fields", "order", "orders", "phase", "phases",
        "site", "sites", "end", "ends", "side", "sides", "position", "positions",
        "composition", "elderly", "stage", "stages", "number of", "kind", "kinds",
    ]

    /// Terimin başında bir cümle parçası olduğunu ele veren sözcükler — sözlük
    /// çıkarımının zaman zaman bıraktığı "These are…", "Found in…", "Three
    /// types…" gibi artıklar.
    private static let fragmentLeads: Set<String> = [
        "these", "those", "this", "that", "found", "produced", "three", "two",
        "some", "many", "used", "present", "various", "several", "including",
        "contains", "consist", "consists", "known", "called", "both", "all",
        "each", "other", "such", "their", "its", "there", "here", "when", "where",
    ]

    /// Terimin sonunda bir bağlaç/edat olması da parça demektir ("function to",
    /// "produced by", "found in").
    private static let fragmentTails: Set<String> = [
        "to", "by", "in", "of", "and", "or", "with", "for", "from", "as", "the",
        "a", "an", "is", "are",
    ]

    /// Kavram taşımayan bir terim mi — kesişim listesinden elenmeli mi.
    static func isGeneric(_ folded: String) -> Bool {
        let words = folded.split(separator: " ").map(String.init)
        guard let first = words.first, let last = words.last else { return true }

        if fragmentLeads.contains(first) { return true }
        if words.count > 1, fragmentTails.contains(last) { return true }
        if words.allSatisfy({ genericWords.contains($0) }) { return true }
        // Tek kelimelik terim: kısa ya da genelse ele.
        if words.count == 1, folded.count < 6 || genericWords.contains(folded) {
            return true
        }
        return false
    }
}
