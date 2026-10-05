import SwiftUI

/// A text field that suggests names you already have while you type, and lets
/// you commit either one of them or something new.
///
/// Two deliberate rules, so that nothing is ambiguous:
///
/// - **Enter commits exactly what you typed.** It never silently picks the top
///   suggestion. Spelling variants are still caught downstream, because the
///   lookup folds case and Turkish letters before deciding it is a new name.
/// - **Clicking a suggestion commits that suggestion.**
struct NameSuggestField: View {
    let placeholder: String

    /// Names already on record, offered as suggestions.
    let suggestions: [String]

    /// Receives the committed name. The field clears itself afterwards.
    let onCommit: (String) -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var query: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Suggestions worth showing: those containing the query, minus the one
    /// that is already exactly what was typed (Enter covers that case).
    private var matches: [String] {
        guard !query.isEmpty else { return [] }
        return suggestions
            .filter { SearchText.contains($0, query: query) && !SearchText.sameName($0, query) }
            .prefix(6)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                TextField(placeholder, text: $text)
                    .focused($isFocused)
                    .onSubmit { commit(query) }

                Button {
                    commit(query)
                } label: {
                    Image(systemName: "return")
                }
                .help("Yazdığını ekle")
                .disabled(query.isEmpty)
            }

            if isFocused && !matches.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(matches, id: \.self) { name in
                        Button {
                            commit(name)
                        } label: {
                            HStack {
                                Text(name)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                        }
                        .buttonStyle(.plain)

                        if name != matches.last {
                            Divider()
                        }
                    }
                }
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func commit(_ rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        onCommit(name)
        text = ""
    }
}
