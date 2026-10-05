import SwiftUI

/// A small rounded label, optionally with a remove button.
struct Chip: View {
    let text: String
    var color: Color = .gray
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.callout)

            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.plain)
                .help("Kaldır")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.25), in: Capsule())
    }
}
