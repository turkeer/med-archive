import SwiftUI

extension View {
    /// Fixes how a `TextField` behaves inside a macOS grouped `Form`.
    ///
    /// Two things go wrong by default, and they have the same cause: the form
    /// lays the label out on the leading side and the control on the trailing
    /// side, with the control's contents aligned trailing too. So the editable
    /// area sits at the right edge of the row — you have to click the right
    /// part of it to start typing — and the text grows leftwards from a fixed
    /// caret as you type.
    ///
    /// Leading alignment puts the caret where the text starts and makes the
    /// whole field behave the way a text field should.
    func formTextField() -> some View {
        multilineTextAlignment(.leading)
    }

    /// For a field whose label is only there to act as a placeholder: drops
    /// the label from the row's layout so the field takes the full width and
    /// is clickable across all of it.
    func borderlessFormTextField() -> some View {
        labelsHidden()
            .multilineTextAlignment(.leading)
    }
}
