import SwiftUI

/// Picks a period from the school's fixed weekday timetable, writing the real
/// times into the lecture. One tap replaces setting two clocks by hand.
///
/// There is no mode to get out of sync: the buttons only write
/// `startMinutes` / `endMinutes`, and what is highlighted is read back from
/// those same values. A time that matches no period reads as a custom time.
struct SlotPicker: View {
    @Binding var startMinutes: Int?
    @Binding var endMinutes: Int?

    /// Hovering a number shows its hours in the line below, so the row can
    /// stay as bare numbers — nine times written out would not fit the column,
    /// and a hint long enough to explain that got truncated anyway. Each
    /// button also carries its hours as a tooltip.
    @State private var hoveredSlot: LessonSlot?

    private var selected: [LessonSlot] {
        LessonSlot.span(start: startMinutes, end: endMinutes)
    }

    private var hasTime: Bool {
        startMinutes != nil || endMinutes != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 9),
                spacing: 4
            ) {
                ForEach(LessonSlot.all) { slot in
                    button(for: slot)
                }
            }

            HStack(spacing: 10) {
                if !selected.isEmpty {
                    Picker("Süre", selection: lengthBinding) {
                        Text("1 ders").tag(1)
                        Text("2 ders").tag(2)
                        Text("3 ders").tag(3)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 200)
                }

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if hasTime {
                    Button("Temizle") {
                        startMinutes = nil
                        endMinutes = nil
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func button(for slot: LessonSlot) -> some View {
        let isSelected = selected.contains(slot)

        return Button {
            // Keep the current length when moving to another period.
            let range = slot.range(lasting: max(1, selected.count))
            startMinutes = range.start
            endMinutes = range.end
        } label: {
            Text("\(slot.number)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .background(
                    isSelected ? Color.accentColor : Color.secondary.opacity(0.14),
                    in: RoundedRectangle(cornerRadius: 5)
                )
                .contentShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help(slot.longLabel)
        .onHover { inside in
            if inside {
                hoveredSlot = slot
            } else if hoveredSlot == slot {
                hoveredSlot = nil
            }
        }
    }

    /// Reads the length back from the times, and writes a new one by extending
    /// from whichever period is first.
    private var lengthBinding: Binding<Int> {
        Binding(
            get: { max(1, selected.count) },
            set: { count in
                guard let first = selected.first else { return }
                let range = first.range(lasting: count)
                startMinutes = range.start
                endMinutes = range.end
            }
        )
    }

    private var statusText: String {
        if let hoveredSlot {
            return hoveredSlot.longLabel
        }
        if let label = LessonSlot.spanLabel(start: startMinutes, end: endMinutes) {
            return "\(label) · \(TimeOfDay.rangeText(start: startMinutes, end: endMinutes))"
        }
        if !hasTime {
            return "Saat seçilmedi"
        }
        return "Özel saat · \(TimeOfDay.rangeText(start: startMinutes, end: endMinutes))"
    }
}
