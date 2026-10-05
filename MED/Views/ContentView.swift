import SwiftUI

/// Stage 1 keeps the whole app in one column. The permanent sidebar
/// (Takvim / Dersler / Akademisyenler / Komiteler / Etiketler) arrives once
/// there is something to put in it.
struct ContentView: View {
    var body: some View {
        NavigationStack {
            LectureListView()
        }
    }
}
