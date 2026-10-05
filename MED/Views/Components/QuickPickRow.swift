import SwiftData
import SwiftUI

/// A small fixed set of records as buttons. Courses and committees both come
/// in handfuls, so picking one should be a single tap, not a search.
struct QuickPickRow: View {
    struct Item: Identifiable {
        let id: PersistentIdentifier
        let label: String
        let colorHex: String
    }

    let items: [Item]
    let selectedID: PersistentIdentifier?

    /// Receives the new choice, or `nil` when the selected item is tapped
    /// again to clear it.
    let pick: (PersistentIdentifier?) -> Void

    var body: some View {
        // Flow, not a grid: equal-width columns truncate a long course name
        // and waste space on a short one.
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(items) { item in
                QuickPickChip(item: item, isSelected: item.id == selectedID) {
                    pick(item.id == selectedID ? nil : item.id)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}

private struct QuickPickChip: View {
    let item: QuickPickRow.Item
    let isSelected: Bool
    let tap: () -> Void

    var body: some View {
        Button(action: tap) {
            HStack(spacing: 5) {
                Circle()
                    .fill(Color(hex: item.colorHex))
                    .frame(width: 7, height: 7)

                Text(item.label)
                    .lineLimit(1)
            }
            .font(.callout)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                isSelected
                    ? Color(hex: item.colorHex).opacity(0.38)
                    : Color.secondary.opacity(0.12),
                in: Capsule()
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(isSelected ? L.pick("Seçimi kaldır", "Clear selection") : item.label)
    }
}
