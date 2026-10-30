import SwiftData
import SwiftUI

/// A lecture as something to read, which is what you want nine times out of
/// ten: what was this lesson, and where are its slides.
///
/// The detail column used to be the editor and nothing else, so arriving here
/// from the calendar meant landing in a seven-section form — eleven course
/// chips with one of them filled in, a period picker, an empty notes box — and
/// finding the slide at the very bottom. Everything above it was for changing
/// the record, which is not why you clicked a lesson.
///
/// Two rules keep it short:
///
/// - **An empty field is not shown at all.** No notes means no notes section,
///   rather than an empty box taking up the room.
/// - **Files come first**, under the facts. They are the thing being looked
///   for; in the editor they are last, after six sections of choosers.
struct LectureReadView: View {
    let lecture: Lecture

    @Query private var allLectures: [Lecture]

    var body: some View {
        Form {
            facts

            LectureFilesSection(lecture: lecture, showsControls: false)

            if !notes.isEmpty {
                Section(L.notes) {
                    Text(notes)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if !lecture.tags.isEmpty {
                Section(L.tags) {
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(lecture.tags) { tag in
                            Chip(text: tag.name, color: Color(hex: tag.colorHex))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Facts

    private var facts: some View {
        Section {
            if let course = lecture.course {
                LabeledContent(L.course) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(hex: course.colorHex))
                            .frame(width: 8, height: 8)

                        Text(course.name.isEmpty ? L.unnamed : course.name)

                        FormatBadge(format: lecture.format)
                    }
                }
            } else {
                LabeledContent(L.format) {
                    FormatBadge(format: lecture.format)
                }
            }

            LabeledContent(L.pick("Tarih", "Date")) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(L.format(lecture.date, Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide).year()))

                    if !lecture.scheduleText.isEmpty {
                        Text(lecture.scheduleText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let instructor = lecture.instructor, !instructor.displayName.isEmpty {
                LabeledContent(L.instructor) {
                    Text(instructor.displayName)
                }
            }

            if let committee = lecture.committee {
                LabeledContent(L.committee) {
                    Text(committee.fullLabel.isEmpty ? L.unnamed : committee.fullLabel)
                }
            }

            // Said out loud, because the slides live on the topic rather than
            // on the record: seeing "two lessons" explains why a file attached
            // to the other half shows up here.
            if parts.count > 1 {
                LabeledContent(L.pick("Bu konu", "This topic")) {
                    Text(L.lessonCount(parts.count) + " · " + LectureGrouping.slotLabel(for: parts))
                }
            }
        }
    }

    private var notes: String {
        lecture.notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parts: [Lecture] {
        LectureGrouping.parts(of: lecture, among: allLectures)
    }
}
