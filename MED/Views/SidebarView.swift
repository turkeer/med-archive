import SwiftUI

/// The permanent leading column.
struct SidebarView: View {
    @Binding var section: SidebarSection?

    var body: some View {
        List(selection: $section) {
            ForEach(SidebarSection.allCases) { item in
                Label(item.title, systemImage: item.symbolName)
                    .tag(item)
            }
        }
        .navigationTitle("MED")
        .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
    }
}
