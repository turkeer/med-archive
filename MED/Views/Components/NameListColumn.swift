import SwiftUI
import SwiftData

/// The middle column for courses, instructors, committees and tags. They all
/// behave the same way — a list of named records, add and delete — so they
/// share one implementation and differ only in what each row says.
///
/// Adding inserts an empty record and selects it, so you rename it in the
/// detail pane instead of answering a dialog first.
struct NameListColumn<Item: PersistentModel>: View where Item.ID == PersistentIdentifier {
    let title: String
    let items: [Item]
    @Binding var selection: PersistentIdentifier?

    let name: (Item) -> String
    let subtitle: (Item) -> String
    /// A dot before the name, where the record carries a colour.
    let accent: (Item) -> Color?
    let make: () -> Item

    var emptyMessage = L.pick("Henüz kayıt yok.", "Nothing here yet.")
    var addLabel = L.pick("Yeni", "New")

    @Environment(\.modelContext) private var context

    var body: some View {
        List(selection: $selection) {
            ForEach(items) { item in
                HStack(spacing: 8) {
                    if let accent = accent(item) {
                        Circle()
                            .fill(accent)
                            .frame(width: 9, height: 9)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(displayName(for: item))
                            .font(.body)

                        if !subtitle(item).isEmpty {
                            Text(subtitle(item))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .onDelete(perform: delete)
        }
        .navigationTitle(title)
        .overlay {
            if items.isEmpty {
                ContentUnavailableView(
                    emptyMessage,
                    systemImage: "tray",
                    description: Text(L.pick("Sağ üstteki + ile ekle.", "Add one with the + at the top right."))
                )
            }
        }
        .toolbar {
            ToolbarItem {
                Button(action: add) {
                    Label(addLabel, systemImage: "plus")
                }
            }
        }
    }

    private func displayName(for item: Item) -> String {
        let text = name(item).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? L.unnamed : text
    }

    private func add() {
        let item = make()
        context.insert(item)
        selection = item.persistentModelID
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            context.delete(items[index])
        }
    }
}
