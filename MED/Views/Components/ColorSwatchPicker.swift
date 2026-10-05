import SwiftUI

/// Picks one of the palette colours, storing it as a hex string.
struct ColorSwatchPicker: View {
    @Binding var hex: String

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 30), spacing: 8, alignment: .leading)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(Palette.hexes, id: \.self) { candidate in
                Button {
                    hex = candidate
                } label: {
                    Circle()
                        .fill(Color(hex: candidate))
                        .frame(width: 22, height: 22)
                        .overlay {
                            if candidate.caseInsensitiveCompare(hex) == .orderedSame {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .shadow(radius: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(candidate)
            }
        }
        .padding(.vertical, 2)
    }
}
