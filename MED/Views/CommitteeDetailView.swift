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
        .navigationSubtitle("\(committee.dateRangeText) · " + L.sessionCount(committee.lectures.count))
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
