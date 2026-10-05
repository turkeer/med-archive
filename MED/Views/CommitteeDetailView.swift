import SwiftUI
import SwiftData

/// A committee, its date range, and its lectures grouped by course.
struct CommitteeDetailView: View {
    @Bindable var committee: Committee

    @Environment(\.modelContext) private var context

    var body: some View {
        Form {
            Section("Komite") {
                TextField("Ad", text: $committee.name, prompt: Text("Komite I"))

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

            // Committees span several courses, so grouping is the readable form.
            LectureLinkList(lectures: committee.lectures, groupByCourse: true)
        }
        .formStyle(.grouped)
        .navigationTitle(committee.name.isEmpty ? "(adsız komite)" : committee.name)
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

    /// Committee dates mark whole days, so the time part is dropped.
    private func dayBinding(for keyPath: ReferenceWritableKeyPath<Committee, Date>) -> Binding<Date> {
        Binding(
            get: { committee[keyPath: keyPath] },
            set: { committee[keyPath: keyPath] = Calendar.current.startOfDay(for: $0) }
        )
    }
}
