import SwiftUI

extension View {
    /// macOS'ta `.link` buton stili; iOS'ta `.link` yok, ona en yakın okunan
    /// sade/tint'li bir stil. Tek yerden değiştirilebilsin diye burada.
    @ViewBuilder
    func linkButtonStyle() -> some View {
        #if os(macOS)
        self.buttonStyle(.link)
        #else
        self.buttonStyle(.borderless)
        #endif
    }
}
