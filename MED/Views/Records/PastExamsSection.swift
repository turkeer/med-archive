import QuickLook
import SwiftData
import SwiftUI

/// A committee's past papers: last year's exam and the ones before it.
///
/// They live under the committee because that is what you revise for and
/// where you go looking for them. Each paper is a row you can open to get at
/// its files, so adding one does not take you to another screen.
struct PastExamsSection: View {
    let committee: Committee

    @Environment(\.modelContext) private var context
    @Environment(LibraryRoot.self) private var library

    @State private var previewURL: URL?
    @State private var expanded: Set<PersistentIdentifier> = []

    /// Presentation and target are kept apart on purpose.
    ///
    /// A synthesised `isPresented` binding that cleared the target in its
    /// setter lost it: dismissing the picker runs the setter, and by the time
    /// the completion handler asked which paper to attach to, the answer was
    /// already gone — so files silently went nowhere. `isImporting` is the
    /// only thing dismissal touches; `importTarget` survives until the
    /// handler has used it.
    @State private var isImporting = false
    @State private var importTarget: PersistentIdentifier?

    /// Newest paper first, Turkish before English within a year.
    private var exams: [PastExam] {
        committee.pastExams.sorted { one, other in
            if one.startYear != other.startYear { return one.startYear > other.startYear }
            return one.language.rawValue < other.language.rawValue
        }
    }

    var body: some View {
        Section {
            if exams.isEmpty {
                Text(L.pick("Bu komite için çıkmış sınav eklenmemiş.", "No past papers added for this committee."))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(exams) { exam in
                    examRow(exam)
                }
            }

            Button(action: addExam) {
                Label(L.pick("Çıkmış sınav ekle", "Add a past paper"), systemImage: "plus")
            }
        } header: {
            Text(L.pick("Çıkmışlar", "Past papers"))
        } footer: {
            Text(L.pick(
                "Her çıkmış için yıl ve dil tutuluyor. Dosyalar kopyalanmaz, yalnızca yerleri saklanır.",
                "Each paper keeps a year and a language. Files are not copied, only their locations are remembered."
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: FileAttaching.allowedTypes,
            allowsMultipleSelection: true
        ) { result in
            attach(result)
        }
        .quickLookPreview($previewURL)
    }

    // MARK: Rows

    private func examRow(_ exam: PastExam) -> some View {
        DisclosureGroup(isExpanded: expansion(of: exam)) {
            ForEach(exam.files.sorted { $0.fileName < $1.fileName }) { file in
                FileRow(
                    file: file,
                    url: file.url(root: library.url),
                    preview: { previewURL = $0 },
                    remove: { remove(file) }
                )
            }

            // Not a segmented control: inside a DisclosureGroup in a grouped
            // Form it is taller than the row and gets clipped by the one
            // above. A dropdown also matches the year picker below it.
            Picker(L.pick("Dil", "Language"), selection: languageBinding(exam)) {
                ForEach(ExamLanguage.allCases) { language in
                    Text(language.title).tag(language)
                }
            }

            Picker(L.pick("Yıl", "Year"), selection: yearBinding(exam)) {
                ForEach(AcademicYear.choices(including: exam.startYear), id: \.self) { year in
                    Text(AcademicYear.label(startYear: year)).tag(year)
                }
            }

            HStack {
                Button {
                    importTarget = exam.persistentModelID
                    isImporting = true
                } label: {
                    Label(L.addFile, systemImage: "paperclip")
                }

                Spacer()

                Button(L.pick("Bu çıkmışı sil", "Delete this paper"), role: .destructive) {
                    context.delete(exam)
                }
                .font(.caption)
            }
        } label: {
            HStack(spacing: 8) {
                Text(exam.yearLabel)
                    .font(.body.monospacedDigit())

                Text(exam.language.badge)
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.18), in: RoundedRectangle(cornerRadius: 3))

                Spacer()

                if exam.files.isEmpty {
                    Text(L.pick("dosya yok", "no files"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label("\(exam.files.count)", systemImage: "paperclip")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Bindings

    private func expansion(of exam: PastExam) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(exam.persistentModelID) },
            set: { isOpen in
                if isOpen {
                    expanded.insert(exam.persistentModelID)
                } else {
                    expanded.remove(exam.persistentModelID)
                }
            }
        )
    }

    private func languageBinding(_ exam: PastExam) -> Binding<ExamLanguage> {
        Binding(get: { exam.language }, set: { exam.language = $0 })
    }

    private func yearBinding(_ exam: PastExam) -> Binding<Int> {
        Binding(get: { exam.startYear }, set: { exam.startYear = $0 })
    }

    // MARK: Actions

    /// A new paper opens expanded: you are adding it to put files in it.
    private func addExam() {
        let exam = PastExam(startYear: AcademicYear.startYear())
        context.insert(exam)
        exam.committee = committee
        expanded.insert(exam.persistentModelID)
    }

    private func attach(_ result: Result<[URL], Error>) {
        let wanted = importTarget
        importTarget = nil

        guard let wanted,
              let target = exams.first(where: { $0.persistentModelID == wanted })
        else { return }

        for file in FileAttaching.records(for: result, library: library, existing: target.files) {
            context.insert(file)
            target.files.append(file)
        }
    }

    private func remove(_ file: LectureFile) {
        if let owner = file.exam {
            owner.files.removeAll { $0.persistentModelID == file.persistentModelID }
        }
        context.delete(file)
    }
}
