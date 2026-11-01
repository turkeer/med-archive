import SwiftData
import SwiftUI

/// Linking a lecture to others as one topic that runs across several days.
///
/// The same-day rule in `LectureGrouping` already folds a subject taught over
/// two periods of one day; this is for the case it cannot see — the same
/// subject continued on another day. The link is explicit on purpose: two
/// lessons that merely share a generic title ("Anatomi lab") on different days
/// are not one topic, and no rule can tell those apart from ones that are.
///
/// Tapping a candidate joins its lesson to this topic; a day already in the
/// topic can be removed as a whole. Joined lessons share their slides and read
/// as parts (1), (2), (3). Only the same course is offered, which is where a
/// continuation lives and keeps the list short.
struct TopicLinkSheet: View {
    let lecture: Lecture

    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Lecture.date, order: .reverse) private var allLectures: [Lecture]

    @State private var query = ""

    private struct TopicDay {
        let day: Date
        let lectures: [Lecture]
    }

    /// This topic's days other than this lecture's own, earliest first.
    private var otherDays: [TopicDay] {
        let ownDay = Calendar.current.startOfDay(for: lecture.date)
        let grouped = Dictionary(grouping: LectureGrouping.parts(of: lecture, among: allLectures)) {
            Calendar.current.startOfDay(for: $0.date)
        }
        return grouped
            .filter { $0.key != ownDay }
            .map { TopicDay(day: $0.key, lectures: $0.value) }
            .sorted { $0.day < $1.day }
    }

    /// Lectures that could join: the same course (when this one has one),
    /// never one already in the topic, matching the search.
    private var candidates: [Lecture] {
        let partIDs = Set(LectureGrouping.parts(of: lecture, among: allLectures).map(\.persistentModelID))
        let courseID = lecture.course?.persistentModelID
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)

        return allLectures.filter { other in
            guard !partIDs.contains(other.persistentModelID) else { return false }
            if let courseID, other.course?.persistentModelID != courseID { return false }
            if !needle.isEmpty, !SearchText.contains(other.displayTitle, query: needle) { return false }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(L.pick("Konuyu günlere yay", "Link topic across days"))
                .font(.headline)
                .padding(.top, 14)

            Form {
                if !otherDays.isEmpty {
                    Section(L.pick("Bu konunun günleri", "Days in this topic")) {
                        ForEach(otherDays, id: \.day) { entry in
                            dayRow(entry)
                        }
                    }
                }

                Section {
                    TextField(L.search, text: $query, prompt: Text(L.pick("Konu ara", "Search topics")))
                        .formTextField()

                    if lecture.course == nil {
                        Text(L.pick(
                            "Önce bu derse bir ders (course) seç; adaylar aynı dersten gelir.",
                            "Choose a course for this lecture first; candidates come from the same course."
                        ))
                            .foregroundStyle(.secondary)
                    } else if candidates.isEmpty {
                        Text(L.pick("Bağlanacak başka oturum yok.", "No other sessions to link."))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(candidates) { candidate in
                            candidateRow(candidate)
                        }
                    }
                } header: {
                    Text(L.pick("Aynı dersin öbür günleri", "Other days of this course"))
                } footer: {
                    Text(L.pick(
                        "Eklediğin oturumlar bu konuyla tek sayılır ve slaytları ortak olur.",
                        "Sessions you add count as this one topic and share its slides."
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button(L.close) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 520, height: 640)
    }

    private func dayRow(_ entry: TopicDay) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.lectures.first?.displayTitle ?? L.untitled)
                Text(dateLine(for: entry.day, entry.lectures))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                if let member = entry.lectures.first {
                    LectureGrouping.detachDay(of: member, among: allLectures)
                }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .help(L.pick("Bu günü konudan ayır", "Remove this day from the topic"))
        }
    }

    private func candidateRow(_ candidate: Lecture) -> some View {
        Button {
            LectureGrouping.link(lecture, with: candidate, among: allLectures)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.displayTitle)
                    Text(dateLine(for: candidate.date, [candidate]))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "plus.circle")
                    .foregroundStyle(Color.accentColor)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func dateLine(for day: Date, _ lectures: [Lecture]) -> String {
        let label = L.format(day, Date.FormatStyle.dateTime.weekday(.abbreviated).day().month())
        return "\(label) · \(LectureGrouping.slotLabel(for: lectures))"
    }
}
