import SwiftUI

/// A toolbar delete button that always asks first.
struct DeleteRecordButton: View {
    let question: String
    let explanation: String
    let perform: () -> Void

    @State private var isConfirming = false

    var body: some View {
        Button(role: .destructive) {
            isConfirming = true
        } label: {
            Label(L.delete, systemImage: "trash")
        }
        .confirmationDialog(question, isPresented: $isConfirming) {
            Button(L.delete, role: .destructive, action: perform)
            Button(L.cancel, role: .cancel) {}
        } message: {
            Text(explanation)
        }
    }
}
