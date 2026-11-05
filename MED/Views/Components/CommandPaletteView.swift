import SwiftUI

/// The ⌘K command palette: a Spotlight-style overlay to jump to any section or
/// run an app action without reaching for the sidebar or the menus.
///
/// Fills the window above everything else (placed in `ContentView`'s overlay),
/// dims what's behind, and centres a search card near the top. Typing filters;
/// ↑/↓ move the highlight; Return runs it; Esc or a click outside closes it.
///
/// It shares the window's `nav`, so a jump takes effect the moment you pick it.
struct CommandPaletteView: View {
    /// Built by `ContentView` each time the palette opens, so the run-closures
    /// capture the live context (the JSON export needs it).
    let actions: [CommandAction]

    @Environment(AppNavigation.self) private var nav

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var fieldFocused: Bool

    private var results: [CommandAction] {
        CommandPalette.filter(actions, query: query)
    }

    var body: some View {
        ZStack(alignment: .top) {
            // The dimmed backdrop. A click anywhere outside the card closes.
            Rectangle()
                .fill(.black.opacity(0.14))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { close() }

            card
                .padding(.top, 72)
        }
        // Arrow and Esc handling lives on the whole overlay so it works even
        // while the text field holds focus (a single-line field ignores ↑/↓).
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.escape) { close(); return .handled }
        .onChange(of: query) { _, _ in selection = 0 }
        .onAppear { fieldFocused = true }
    }

    private var card: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(
                    L.pick("Komut ya da bölüm ara…", "Search commands or sections…"),
                    text: $query
                )
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($fieldFocused)
                .onSubmit(runSelected)
            }
            .padding(14)

            Divider()

            if results.isEmpty {
                Text(L.pick("Eşleşme yok", "No matches"))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
            } else {
                resultList
            }
        }
        .frame(width: 540)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12).strokeBorder(.separator)
        )
        .shadow(color: .black.opacity(0.28), radius: 24, y: 10)
    }

    private var resultList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, action in
                        row(action, highlighted: index == selection)
                            .id(index)
                            .contentShape(Rectangle())
                            .onTapGesture { run(action) }
                            .onHover { if $0 { selection = index } }
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 340)
            .onChange(of: selection) { _, index in
                withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(index) }
            }
        }
    }

    private func row(_ action: CommandAction, highlighted: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: action.symbolName)
                .frame(width: 20)
                .foregroundStyle(highlighted ? Color.white : .secondary)
            Text(action.title)
                .foregroundStyle(highlighted ? Color.white : .primary)
            Spacer(minLength: 8)
            if let subtitle = action.subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(highlighted ? Color.white.opacity(0.8) : .secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(highlighted ? Color.accentColor : .clear)
        )
    }

    // MARK: - Actions

    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = (selection + delta + results.count) % results.count
    }

    private func runSelected() {
        guard results.indices.contains(selection) else { return }
        run(results[selection])
    }

    private func run(_ action: CommandAction) {
        close()
        action.run()
    }

    private func close() {
        nav.commandPaletteOpen = false
    }
}
