#if os(iOS)
import SwiftUI

/// iPad'in uygulama-içi ayarları. macOS'ta ayarlar `Settings` sahnesinde (⌘,),
/// iOS'ta öyle bir sahne yok — bu sayfa kenar çubuğundaki dişli düğmesinden
/// açılıyor. Şimdilik dil seçimi; ileride başka ayarlar da buraya gelebilir.
struct AppSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    private var languageBinding: Binding<AppLanguageChoice> {
        Binding(
            get: { AppLanguage.shared.choice },
            set: { AppLanguage.shared.choice = $0 }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(L.pick("Dil", "Language"), selection: languageBinding) {
                        ForEach(AppLanguageChoice.allCases) { choice in
                            Text(choice.endonym).tag(choice)
                        }
                    }
                    .pickerStyle(.inline)
                } header: {
                    Text(L.pick("Uygulama dili", "App language"))
                } footer: {
                    Text(L.pick(
                        "Değişiklik hemen uygulanır; yeniden başlatmaya gerek yok.",
                        "Changes apply immediately; no restart needed."
                    ))
                }
            }
            .navigationTitle(L.pick("Ayarlar", "Settings"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.close) { dismiss() }
                }
            }
        }
    }
}
#endif
