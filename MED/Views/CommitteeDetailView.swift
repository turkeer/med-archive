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
            Section("Komite") {
                TextField("Ad", text: $committee.name, prompt: Text("Introduction to Medicine"))
                    .formTextField()
                TextField("Kısa ad", text: $committee.code, prompt: Text("Komite I"))
                    .formTextField()

                DatePicker(
                    "Başlangıç",
                    selection: dayBinding(for: \.startDate),
                    displayedComponents: .date
                )
                DatePicker(
                    "Bitiş",
                    selection: dayBinding(for: \.endDate),
                    displayedComponents: .date
                )

                LabeledContent("Renk") {
                    ColorSwatchPicker(hex: $committee.colorHex)
                }
            }

            // New lectures pick up their committee from the date on their own.
            // This is for the ones that came before this committee existed.
            Section {
                if pending.isEmpty {
                    Text("Bu aralıkta komitesi boş oturum yok.")
                        .foregroundStyle(.secondary)
                } else {
                    HStack {
                        Text("Bu aralıkta komitesi boş \(pending.count) oturum var.")

                        Spacer()

                        Button("\(committee.shortLabel) olarak ata") {
                            for lecture in pending {
                                lecture.committee = committee
                            }
                        }
                    }
                }
            } header: {
                Text("Geriye dönük atama")
            } footer: {
                Text("Yalnızca komitesi boş olanlara dokunur; elle seçtiğin komiteleri değiştirmez.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Committees span several courses, so grouping is the readable form.
            LectureLinkList(lectures: committee.lectures, groupByCourse: true)
        }
        .formStyle(.grouped)
        .navigationTitle(committee.fullLabel.isEmpty ? "(adsız komite)" : committee.fullLabel)
        .navigationSubtitle("\(committee.dateRangeText) · \(committee.lectures.count) oturum")
        .toolbar {
            ToolbarItem {
                DeleteRecordButton(
                    question: "Bu komite silinsin mi?",
                    explanation: "Oturumlar silinmez — yalnızca komite alanları boşalır."
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
