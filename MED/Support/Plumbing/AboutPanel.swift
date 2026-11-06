import Foundation
#if os(macOS)
import AppKit
#endif

/// The About box, with a line saying who made this.
///
/// Uses the system panel rather than a window of its own: it already knows the
/// app's name, version and copyright, and a bespoke window would be a second
/// thing to keep in step for no gain.
///
/// macOS-only for now: on iOS there is no standard About panel and no menu bar
/// to reach it from; an in-app "Hakkında" screen will come in a later phase.
enum AboutPanel {
#if os(macOS)
    static func show() {
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            NSApplication.AboutPanelOptionKey.applicationName: "MED",
            NSApplication.AboutPanelOptionKey.credits: credits,
        ])
    }

    private static var credits: NSAttributedString {
        // Change the names here if the credit should read differently.
        let lines = [
            L.pick("Ders arşivi — tıp fakültesi için", "Lecture archive — for medical school"),
            "",
            L.pick("Türker Akın & Claude tarafından yapıldı", "Made by Türker Akın & Claude"),
            "",
            L.pick("Kaynak kodu açık · Ticari olmayan kullanım", "Source available · Noncommercial"),
            "github.com/turkeer/med-archive",
        ]

        return NSAttributedString(
            string: lines.joined(separator: "\n"),
            attributes: [
                NSAttributedString.Key.font: NSFont.systemFont(ofSize: 11),
                NSAttributedString.Key.foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
    }
#endif
}
