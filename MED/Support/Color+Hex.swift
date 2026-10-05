import SwiftUI

extension Color {
    /// Builds a colour from a six-digit hex string, with or without a leading "#".
    /// Falls back to grey when the string cannot be read, so a bad value in the
    /// database can never crash a view.
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "#", with: "")

        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else {
            self = .gray
            return
        }

        self.init(
            .sRGB,
            red: Double((value & 0xFF0000) >> 16) / 255,
            green: Double((value & 0x00FF00) >> 8) / 255,
            blue: Double(value & 0x0000FF) / 255,
            opacity: 1
        )
    }
}
