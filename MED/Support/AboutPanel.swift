import AppKit
import Foundation

/// The About box, with a line saying who made this.
///
/// Uses the system panel rather than a window of its own: it already knows the
/// app's name, version and copyright, and a bespoke window would be a second
/// thing to keep in step for no gain.
enum AboutPanel {
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
            L.pick("Açık kaynak · MIT", "Open source · MIT"),
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
}
