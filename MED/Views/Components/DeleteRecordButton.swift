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
            Label("Sil", systemImage: "trash")
        }
        .confirmationDialog(question, isPresented: $isConfirming) {
            Button("Sil", role: .destructive, action: perform)
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text(explanation)
        }
    }
}
