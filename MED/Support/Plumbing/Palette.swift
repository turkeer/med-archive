import Foundation

/// The colours offered for courses, committees and tags.
///
/// A fixed set rather than a free colour picker: it keeps the calendar and the
/// chips looking like one system, and it avoids converting a picked `Color`
/// back into hex, which needs a trip through `NSColor` and its colour space.
enum Palette {
    static let hexes = [
        "E5484D", // kırmızı
        "E54D2E", // kiremit
        "F76B15", // turuncu
        "FFB224", // amber
        "46A758", // yeşil
        "12A594", // çam
        "00A2C7", // camgöbeği
        "0091FF", // mavi
        "3E63DD", // çivit
        "8E4EC6", // mor
        "D6409F", // pembe
        "8B8D98", // gri
    ]

    /// A stable colour for a new record, so that fresh entries do not all
    /// arrive in the same shade.
    static func suggested(for index: Int) -> String {
        hexes[abs(index) % hexes.count]
    }
}
