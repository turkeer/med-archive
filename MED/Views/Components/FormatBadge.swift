import SwiftUI

/// Marks a session as a lab or an exam.
///
/// Only the exceptions are badged. Theoretical sessions are the great
/// majority, so labelling them too would put a badge on nearly every row and
/// tell you nothing.
struct FormatBadge: View {
    let format: LectureFormat

    /// The lab badge borrows its row's colour — it only needs to be legible
    /// against whatever it sits on.
    var tint: Color = .secondary

    var body: some View {
        switch format {
        case .theoretical:
            EmptyView()
        case .practical:
            badge(Text(format.badge), fill: tint.opacity(0.22))
        case .exam:
            // An exam is not a variation on a lesson, it is what the lessons
            // were for, so it gets a colour of its own instead of the row's
            // and reads at a glance in a month of ordinary sessions.
            badge(
                Text(format.badge).foregroundStyle(Color.white),
                fill: Color.orange.opacity(0.9)
            )
        }
    }

    private func badge<Content: View>(_ content: Content, fill: Color) -> some View {
        content
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(fill, in: RoundedRectangle(cornerRadius: 3))
    }
}
