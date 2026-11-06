import SwiftUI

/// The permanent leading column.
struct SidebarView: View {
    @Binding var section: SidebarSection?

    #if os(iOS)
    // iOS'ta Settings sahnesi yok; ayarlara (dil vb.) buradaki dişliden ulaşılır.
    @State private var showingSettings = false
    #endif

    var body: some View {
        List(selection: $section) {
            ForEach(SidebarSection.allCases) { item in
                Label(item.title, systemImage: item.symbolName)
                    .tag(item)
            }
        }
        .navigationTitle("MED")
        .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel(L.pick("Ayarlar", "Settings"))
            }
        }
        .sheet(isPresented: $showingSettings) {
            AppSettingsSheet()
        }
        #endif
    }
}
