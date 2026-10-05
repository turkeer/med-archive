import SwiftUI

/// Lays its subviews out in rows, each one sized to its own content, wrapping
/// to the next row when the next subview does not fit.
///
/// An adaptive `LazyVGrid` cannot do this: its columns are all the same width,
/// so a long course name gets truncated while a short one leaves the rest of
/// its column empty. Sizing each chip to its text means nothing is cut off and
/// a row holds as many as actually fit.
///
/// The order is left as given — alphabetical, for the course and committee
/// rows. Reordering to squeeze out the occasional extra row would make chips
/// move about as courses are added or renamed, and finding the one you want is
/// worth more than a row of height.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    private struct Item {
        let index: Int
        let size: CGSize
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = rows(maxWidth: maxWidth, subviews: subviews)

        let width = rows.map { row in
            row.reduce(0) { $0 + $1.size.width } + spacing * CGFloat(max(0, row.count - 1))
        }
        .max() ?? 0

        let height = rows.reduce(0) { total, row in
            total + (row.map(\.size.height).max() ?? 0)
        } + lineSpacing * CGFloat(max(0, rows.count - 1))

        return CGSize(width: maxWidth.isFinite ? min(width, maxWidth) : width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var y = bounds.minY

        for row in rows(maxWidth: bounds.width, subviews: subviews) {
            var x = bounds.minX
            let rowHeight = row.map(\.size.height).max() ?? 0

            for item in row {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + (rowHeight - item.size.height) / 2),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }

            y += rowHeight + lineSpacing
        }
    }

    private func rows(maxWidth: CGFloat, subviews: Subviews) -> [[Item]] {
        var rows: [[Item]] = []
        var current: [Item] = []
        var currentWidth: CGFloat = 0

        for index in subviews.indices {
            let ideal = subviews[index].sizeThatFits(.unspecified)

            // A single name wider than the whole row is the one case where
            // something has to give; it takes the row and truncates.
            let size = CGSize(
                width: maxWidth.isFinite ? min(ideal.width, maxWidth) : ideal.width,
                height: ideal.height
            )

            let needed = current.isEmpty ? size.width : currentWidth + spacing + size.width

            if !current.isEmpty && needed > maxWidth {
                rows.append(current)
                current = [Item(index: index, size: size)]
                currentWidth = size.width
            } else {
                current.append(Item(index: index, size: size))
                currentWidth = needed
            }
        }

        if !current.isEmpty {
            rows.append(current)
        }

        return rows
    }
}
