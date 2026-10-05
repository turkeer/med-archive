import SwiftUI

/// Marks a session as a lab or an exam.
///
/// Only the exceptions are badged. Theoretical sessions are the great
/// majority, so labelling them too would put a badge on nearly every row and
/// tell you nothing.
///
/// Both badges are solid with white text rather than a faint tint of the row's
/// own colour. A lab and an exam are the two sessions you cannot afford to
/// miss while scanning a month, and a 22%-opacity letter is exactly as easy to
/// skip over as the rest of the row.
///
/// Two different colours, because two solid badges in the same red would read
/// as the same thing at a glance — which is the one job a badge has.
struct FormatBadge: View {
    let format: LectureFormat

    var body: some View {
        switch format {
        case .theoretical:
            EmptyView()
        case .practical:
            badge(fill: Color.red)
        case .exam:
            badge(fill: Color.purple)
        }
    }

    private func badge(fill: Color) -> some View {
        Text(format.badge)
            .font(.system(size: 10, weight: .heavy))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(fill, in: RoundedRectangle(cornerRadius: 3))
    }
}
