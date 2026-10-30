import SwiftUI
import SwiftData

/// A committee, its date range, and its lectures grouped by course.
struct CommitteeDetailView: View {
    @Bindable var committee: Committee

    @Environment(\.modelContext) private var context

    /// Needed so the pending count updates as lectures are assigned.
    @Query private var allLectures: [Lecture]

    var body: some View {
        Form {
            Section(L.committee) {
                TextField(L.name, text: $committee.name, prompt: Text("Introduction to Medicine"))
                    .formTextField()
                TextField(L.pick("Kısa ad", "Short name"), text: $committee.code, prompt: Text(L.pick("Komite I", "Committee I")))
                    .formTextField()

                DatePicker(
                    L.pick("Başlangıç", "Starts"),
                    selection: dayBinding(for: \.startDate),
                    displayedComponents: .date
                )
                DatePicker(
                    L.pick("Bitiş", "Ends"),
                    selection: dayBinding(for: \.endDate),
                    displayedComponents: .date
                )

                LabeledContent(L.color) {
                    ColorSwatchPicker(hex: $committee.colorHex)
                }
            }

            PastExamsSection(committee: committee)

            // New lectures pick up their committee from the date on their own.
            // This is for the ones that came before this committee existed.
            Section {
                if pending.isEmpty {
                    Text(L.pick("Bu aralıkta komitesi boş oturum yok.", "No sessions in this range are missing a committee."))
                        .foregroundStyle(.secondary)
                } else {
                    HStack {
                        Text(L.pick(
                            "Bu aralıkta komitesi boş \(pending.count) oturum var.",
                            "\(pending.count) sessions in this range have no committee."
                        ))

                        Spacer()

                        Button(L.pick("\(committee.shortLabel) olarak ata", "Set them to \(committee.shortLabel)")) {
                            for lecture in pending {
                                lecture.committee = committee
                            }
                        }
                    }
                }
            } header: {
                Text(L.pick("Geriye dönük atama", "Backfill"))
            } footer: {
                Text(L.pick(
                    "Yalnızca komitesi boş olanlara dokunur; elle seçtiğin komiteleri değiştirmez.",
                    "Touches only the ones with no committee; it never changes a committee you set by hand."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Committees span several courses, so grouping is the readable form.
            LectureLinkList(lectures: committee.lectures, groupByCourse: true)
        }
        .formStyle(.grouped)
        .navigationTitle(committee.fullLabel.isEmpty ? L.pick("(adsız komite)", "(unnamed committee)") : committee.fullLabel)
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem {
                DeleteRecordButton(
                    question: L.pick("Bu komite silinsin mi?", "Delete this committee?"),
                    explanation: L.pick(
                        "Oturumlar silinmez, yalnızca komite alanları boşalır. Bu komitenin çıkmış sınav kayıtları ise silinir — diskteki PDF'lere dokunulmaz.",
                        "The sessions stay; only their committee field is cleared. This committee's past-paper records are deleted — the PDFs on disk are untouched."
                    )
                ) {
                    context.delete(committee)
                }
            }
        }
    }

    /// Lectures inside this committee's range that have no committee yet.
    private var subtitle: String {
        [
            committee.dateRangeText,
            L.sessionCount(committee.lectures.count),
            coverageText,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    /// Topics in this committee that have a file on them.
    ///
    /// Topics rather than sessions, matching the rows below, and counted only
    /// over the ones whose day has come — a committee that starts next week is
    /// not a committee missing all its slides. The ones still ahead are said
    /// separately rather than folded into the fraction.
    ///
    /// `nil` when nothing has been taught yet: "0/0 konuda slayt" says
    /// nothing.
    private var coverageText: String? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let groups = LectureGrouping.groups(of: committee.lectures)
        let (due, upcoming) = groups.reduce(into: ([LectureGroup](), 0)) { result, group in
            if calendar.startOfDay(for: group.first.date) > today {
                result.1 += 1
            } else {
                result.0.append(group)
            }
        }

        guard !due.isEmpty else {
            guard upcoming > 0 else { return nil }
            return L.pick("\(upcoming) konu ileride", "\(upcoming) topics to come")
        }

        let covered = due.filter { group in
            group.lectures.contains { !$0.files.isEmpty }
        }.count

        // Not "\(due.count) konudan \(covered)'inde": the Turkish suffix
        // follows the number's last vowel — 0'ında, 3'ünde, 7'sinde, 10'unda —
        // so any single hardcoded ending is wrong for most numbers. A form
        // that needs no suffix is correct for all of them.
        let taught = L.pick(
            "\(covered)/\(due.count) işlenen konuda slayt",
            "slides on \(covered)/\(due.count) topics taught"
        )

        guard upcoming > 0 else { return taught }

        return taught + L.pick(
            " · \(upcoming) konu ileride",
            " · \(upcoming) to come"
        )
    }

    private var pending: [Lecture] {
        allLectures.filter { $0.committee == nil && committee.covers($0.date) }
    }

    /// Committee dates mark whole days, so the time part is dropped.
    private func dayBinding(for keyPath: ReferenceWritableKeyPath<Committee, Date>) -> Binding<Date> {
        Binding(
            get: { committee[keyPath: keyPath] },
            set: { committee[keyPath: keyPath] = Calendar.current.startOfDay(for: $0) }
        )
    }
}
