import SwiftUI

/// Marks a session as a lab.
///
/// Only the exception is badged. Theoretical sessions are the great majority,
/// so labelling them too would put a badge on nearly every row and tell you
/// nothing.
struct FormatBadge: View {
    let format: LectureFormat

    var tint: Color = .secondary

    var body: some View {
        if format == .practical {
            Text(format.badge)
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(tint.opacity(0.22), in: RoundedRectangle(cornerRadius: 3))
        }
    }
}
