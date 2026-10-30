import SwiftUI
import SwiftData

/// The month grid. Days that hold lectures are marked with their committee's
/// colour — or their course's, when there is no committee.
struct CalendarMonthView: View {
    @Binding var visibleMonth: Date
    @Binding var selectedDay: Date?

    /// Drives what the wide trailing column shows: the week grid or one day.
    @Binding var mode: CalendarMode

    @Query private var lectures: [Lecture]

    private let calendar = Calendar.current

    private var grid: MonthGrid {
        MonthGrid(containing: visibleMonth)
    }

    /// Lectures keyed by the start of their day, so a cell is one lookup.
    private var byDay: [Date: [Lecture]] {
        Dictionary(grouping: lectures) { calendar.startOfDay(for: $0.date) }
    }

    var body: some View {
        VStack(spacing: 10) {
            monthHeader

            weekdayHeader

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
                spacing: 4
            ) {
                ForEach(grid.days, id: \.self) { day in
                    DayCell(
                        dayNumber: grid.dayNumber(of: day),
                        lectures: byDay[day] ?? [],
                        isInMonth: grid.isInMonth(day),
                        isToday: calendar.isDateInToday(day),
                        isSelected: isSelected(day)
                    ) {
                        select(day)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .navigationTitle(L.calendar)
        .toolbar {
            ToolbarItem {
                Picker(L.pick("Görünüm", "View"), selection: $mode) {
                    ForEach(CalendarMode.allCases) { candidate in
                        Text(candidate.title).tag(candidate)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            ToolbarItem {
                Button(L.pick("Bugün", "Today"), action: goToToday)
            }
        }
    }

    private var monthHeader: some View {
        HStack {
            Button {
                visibleMonth = grid.adding(months: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .help(L.pick("Önceki ay", "Previous month"))

            Spacer()

            Text(grid.title)
                .font(.headline)

            Spacer()

            Button {
                visibleMonth = grid.adding(months: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .help(L.pick("Sonraki ay", "Next month"))
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 4) {
            ForEach(grid.weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func isSelected(_ day: Date) -> Bool {
        guard let selectedDay else { return false }
        return calendar.isDate(day, inSameDayAs: selectedDay)
    }

    private func select(_ day: Date) {
        selectedDay = day

        // Tapping a day from the previous or next month's tail follows it,
        // rather than selecting something the grid is about to stop showing.
        if !grid.isInMonth(day) {
            visibleMonth = day
        }
    }

    private func goToToday() {
        let today = Date()
        visibleMonth = today
        selectedDay = calendar.startOfDay(for: today)
    }
}

/// One day. Shows the day number and a dot per distinct marker colour.
private struct DayCell: View {
    let dayNumber: Int
    let lectures: [Lecture]
    let isInMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let select: () -> Void

    /// One dot per distinct colour, in time order, at most four.
    private var markerColors: [Color] {
        var seen = Set<String>()
        var colors: [Color] = []

        for lecture in lectures.sorted(by: { ($0.startMinutes ?? 0) < ($1.startMinutes ?? 0) }) {
            let hex = lecture.markerColorHex ?? "8B8D98"
            if seen.insert(hex).inserted {
                colors.append(Color(hex: hex))
            }
        }

        return Array(colors.prefix(4))
    }

    var body: some View {
        Button(action: select) {
            VStack(spacing: 4) {
                Text("\(dayNumber)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(isInMonth ? Color.primary : Color.secondary.opacity(0.45))

                HStack(spacing: 3) {
                    ForEach(markerColors.indices, id: \.self) { index in
                        Circle()
                            .fill(markerColors[index])
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(cellBackground, in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.accentColor, lineWidth: 1.5)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(lectures.isEmpty ? "" : L.sessionCount(lectures.count))
    }

    private var cellBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(0.28)
        }
        if isInMonth {
            return Color.secondary.opacity(0.08)
        }
        return .clear
    }
}
