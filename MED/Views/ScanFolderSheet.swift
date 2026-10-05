import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Walks a folder and proposes which session each file belongs to.
///
/// The scan runs when you ask it to and never otherwise. Nothing is applied
/// that is not ticked, and nothing is copied, moved or renamed: a match writes
/// one record pointing at where the file already is.
///
/// Proposals come in three groups because the right response to each differs.
/// A certain match wants a glance; a weak one wants a decision; an unmatched
/// file has no session to join, so applying it makes one.
struct ScanFolderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(LibraryRoot.self) private var library

    @Query private var lectures: [Lecture]
    @Query(sort: \Course.name) private var courses: [Course]

    /// Every file record there is, past papers included: a path already in the
    /// archive is not a finding.
    @Query private var fileRecords: [LectureFile]

    @State private var folder: URL?
    @State private var findings: [ScanFinding] = []
    @State private var hasScanned = false

    /// Rows to apply, by stored path.
    @State private var ticked: Set<String> = []

    /// Where a weak row's proposal was overruled.
    @State private var chosen: [String: PersistentIdentifier] = [:]

    @State private var isChoosingFolder = false
    @State private var outcome: String?

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            footer
        }
        .frame(minWidth: 720, idealWidth: 820, minHeight: 520, idealHeight: 620)
        .fileImporter(
            isPresented: $isChoosingFolder,
            allowedContentTypes: [UTType.folder]
        ) { result in
            if case .success(let url) = result {
                folder = url
                scan()
            }
        }
        .onAppear {
            if folder == nil { folder = library.url }
        }
    }

    // MARK: Chrome

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(folder == nil ? "Klasör seçilmedi" : folderName)
                    .font(.headline)

                if let folder {
                    Text(folder.path(percentEncoded: false))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            Button("Klasör seç…") {
                isChoosingFolder = true
            }

            Button("Tara") {
                scan()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(folder == nil)
        }
        .padding(12)
    }

    private var folderName: String {
        folder?.lastPathComponent ?? ""
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let outcome {
                Label(outcome, systemImage: "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Kapat") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button(applyTitle) {
                apply()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(ticked.isEmpty)
        }
        .padding(12)
    }

    private var applyTitle: String {
        ticked.isEmpty ? "Uygula" : "Uygula (\(ticked.count))"
    }

    @ViewBuilder
    private var content: some View {
        if !hasScanned {
            ContentUnavailableView {
                Label("Klasörü tara", systemImage: "doc.text.magnifyingglass")
            } description: {
                Text("Dosya adındaki tarihe, bulunduğu klasöre ve konu benzerliğine bakarak hangi oturuma ait olduğunu bulur. Hiçbir dosya kopyalanmaz veya taşınmaz, yalnızca yeri kaydedilir.")
            }
        } else if findings.isEmpty {
            ContentUnavailableView {
                Label("Bağlanacak dosya yok", systemImage: "checkmark.circle")
            } description: {
                Text("Bu klasördeki dosyaların hepsi zaten kayıtlı.")
            }
        } else {
            List {
                group(
                    .certain,
                    title: "Kesin eşleşme",
                    note: "Tarih, klasör ve konu birbirini doğruluyor."
                )

                group(
                    .weak,
                    title: "Zayıf eşleşme",
                    note: "Gün doğru görünüyor ama konu kesin değil. Önerilen oturumu değiştirebilirsin."
                )

                group(
                    .unmatched,
                    title: "Eşleşmedi",
                    note: "O güne ait oturum bulunamadı. İşaretlenirse dosya adından yeni bir oturum oluşturulur."
                )
            }
        }
    }

    // MARK: Rows

    private func rows(_ confidence: ScanConfidence) -> [ScanFinding] {
        findings.filter { $0.confidence == confidence }
    }

    @ViewBuilder
    private func group(_ confidence: ScanConfidence, title: String, note: String) -> some View {
        if !rows(confidence).isEmpty {
            Section {
                ForEach(rows(confidence)) { finding in
                    row(finding)
                }
            } header: {
                HStack {
                    Text("\(title) (\(rows(confidence).count))")

                    Spacer()

                    Button(allTicked(rows(confidence)) ? "Hiçbirini seçme" : "Hepsini seç") {
                        toggleAll(rows(confidence))
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                }
            } footer: {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ finding: ScanFinding) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: tickBinding(for: finding))
                .labelsHidden()
                .disabled(!canApply(finding))

            VStack(alignment: .leading, spacing: 3) {
                Text(finding.fileName)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 8) {
                    if let date = finding.name.date {
                        Label {
                            Text(date, format: .dateTime.day().month(.abbreviated).year())
                        } icon: {
                            Image(systemName: "calendar")
                        }
                    } else {
                        Label("Dosya adında tarih yok", systemImage: "calendar.badge.exclamationmark")
                    }

                    if !finding.folderName.isEmpty {
                        Label(finding.folderName, systemImage: "folder")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            }

            Spacer(minLength: 12)

            proposal(for: finding)
                .frame(width: 260, alignment: .leading)
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func proposal(for finding: ScanFinding) -> some View {
        if finding.confidence == .unmatched {
            if finding.canCreateLecture {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Yeni oturum: \(finding.name.topic.isEmpty ? "(başlıksız)" : finding.name.topic)")
                        .lineLimit(1)

                    Text("saati Konular'dan verilir")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Uygulanamaz")
                    .foregroundStyle(.secondary)
            }
        } else if let lecture = target(for: finding) {
            // A weak row's proposal is a menu, so overruling it is one click
            // rather than a trip to Konular after the fact.
            if finding.alternatives.isEmpty {
                lectureLabel(lecture, score: finding.score)
            } else {
                Menu {
                    ForEach(options(for: finding)) { option in
                        Button(option.displayTitle) {
                            chosen[finding.id] = option.persistentModelID
                        }
                    }
                } label: {
                    lectureLabel(lecture, score: finding.score)
                }
                .menuIndicator(.visible)
            }
        }
    }

    private func lectureLabel(_ lecture: Lecture, score: Double) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(lecture.displayTitle)
                .lineLimit(1)

            HStack(spacing: 6) {
                if let course = lecture.course {
                    Text(course.name)
                        .foregroundStyle(Color(hex: course.colorHex))
                }

                Text(LectureGrouping.slotLabel(for: [lecture]))

                Text("%\(Int((score * 100).rounded()))")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// The proposal first, then the day's other topics.
    private func options(for finding: ScanFinding) -> [Lecture] {
        guard let lecture = finding.lecture else { return finding.alternatives }
        return [lecture] + finding.alternatives
    }

    // MARK: Ticks

    private func canApply(_ finding: ScanFinding) -> Bool {
        finding.confidence == .unmatched ? finding.canCreateLecture : finding.lecture != nil
    }

    private func tickBinding(for finding: ScanFinding) -> Binding<Bool> {
        Binding(
            get: { ticked.contains(finding.id) },
            set: { isOn in
                if isOn {
                    ticked.insert(finding.id)
                } else {
                    ticked.remove(finding.id)
                }
            }
        )
    }

    private func allTicked(_ rows: [ScanFinding]) -> Bool {
        let applicable = rows.filter(canApply)
        return !applicable.isEmpty && applicable.allSatisfy { ticked.contains($0.id) }
    }

    private func toggleAll(_ rows: [ScanFinding]) {
        let applicable = rows.filter(canApply)

        if allTicked(rows) {
            for row in applicable { ticked.remove(row.id) }
        } else {
            for row in applicable { ticked.insert(row.id) }
        }
    }

    /// What a row would attach to, the overrule taken into account.
    private func target(for finding: ScanFinding) -> Lecture? {
        guard let id = chosen[finding.id] else { return finding.lecture }

        if let picked = options(for: finding).first(where: { $0.persistentModelID == id }) {
            return picked
        }

        return finding.lecture
    }

    // MARK: Doing the work

    private func scan() {
        guard let folder else { return }

        let urls = FolderScan.files(in: folder)

        findings = FolderScan.findings(
            in: urls,
            lectures: lectures,
            courses: courses,
            library: library,
            attached: Set(fileRecords.map(\.relativePath))
        )

        // The certain ones start ticked and the rest do not. That is the whole
        // difference between the groups: one is a glance, the others a
        // decision, and defaulting a guess to "yes" is how the wrong file ends
        // up on the wrong lecture.
        ticked = Set(findings.filter { $0.confidence == .certain }.map(\.id))
        chosen = [:]
        hasScanned = true
        outcome = nil
    }

    private func apply() {
        var attached = 0
        var created = 0
        var done: Set<String> = []

        for finding in findings where ticked.contains(finding.id) {
            if finding.confidence == .unmatched {
                guard let lecture = makeLecture(from: finding) else { continue }
                attach(finding, to: lecture)
                created += 1
            } else if let lecture = target(for: finding) {
                attach(finding, to: lecture)
                attached += 1
            } else {
                continue
            }

            done.insert(finding.id)
        }

        // Saved now rather than left to autosave: this is a batch of work you
        // just approved, and it should survive the app being quit.
        try? context.save()

        // The applied rows are dropped from the list rather than the folder
        // being walked again. A fresh scan would read `fileRecords`, and the
        // records inserted a moment ago are not in that query's results yet —
        // every file just linked would come back as a finding.
        findings.removeAll { done.contains($0.id) }
        ticked.subtract(done)

        var parts: [String] = []
        if attached > 0 { parts.append("\(attached) dosya bağlandı") }
        if created > 0 { parts.append("\(created) oturum oluşturuldu") }
        outcome = parts.isEmpty ? "Değişen bir şey olmadı" : parts.joined(separator: ", ")
    }

    private func attach(_ finding: ScanFinding, to lecture: Lecture) {
        let record = LectureFile(
            fileName: finding.fileName,
            relativePath: finding.storedPath,
            kind: FileNaming.kind(for: finding.fileName)
        )

        context.insert(record)
        lecture.files.append(record)
    }

    /// A session built from what the file's name and folder say. Deliberately
    /// without a time: the timetable is not in the file name, and a made-up
    /// period would be worse than an empty one.
    private func makeLecture(from finding: ScanFinding) -> Lecture? {
        guard let date = finding.name.date else { return nil }

        let lecture = Lecture(title: finding.name.topic, date: date)
        context.insert(lecture)

        lecture.course = FolderScan.course(named: finding.folderName, among: courses)
        lecture.committee = context.committee(covering: date)

        return lecture
    }
}
