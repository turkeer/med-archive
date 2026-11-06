# Faz 0 — Fizibilite Spike

> Amaç: iPad uyarlamasının **iki belirsizliğini** kanıtlamak. Üretim kodu değil,
> "gidilir mi" cevabı. Yeşil yanarsa `docs/ipad-uyarlama-plani.md` uygulanır.

Bu klasör **bilinçli olarak `MED/` dışında.** Proje `PBXFileSystemSynchronizedRootGroup`
kullandığı için `MED/` altına konan her `.swift` otomatik **macOS** hedefine girer;
buradaki dosyalar iOS-only API (`UIViewRepresentable`, `PencilKit`) içerdiğinden
Mac derlemesini kırardı. Bu yüzden ayrı duruyorlar ve ayrı bir **iOS hedefinde**
derlenmeleri gerekiyor (aşağıya bak).

## Kanıtlanacak iki şey
1. **Konteyner içe alma** — dış bir PDF'i `UIDocumentPicker` ile seç, uygulamanın
   `Documents/` klasörüne kopyala, sonra **security-scoped bookmark olmadan** aç.
   (`ContainerStore.swift`)
2. **Pencil akıcılığı** — büyük bir PDF'i `PDFView` + sayfa-başına `PKCanvasView`
   (`PDFPageOverlayViewProvider` ile) + `.pencilOnly` ile aç. Parmakla gez/zoomla,
   kalemle yaz; **takılıyor mu?** (`PencilPDFReader.swift`)

## Başarı kriteri
- İçe alınan PDF bookmark'sız açılıyor. ✔
- 150–200+ sayfalık, bolca çizim yapılmış bir deste **pürüzsüz** kaydırılıyor,
  kalem gecikmesiz yazıyor. ✔
- Çizimler kapat-aç sonrası yerinde (`PKDrawing` kalıcılığı). ✔

## iPad'de nasıl çalıştırılır (bir kerelik Xcode kurulumu)
Proje şu an macOS-only ve `.pbxproj` elle düzenlenmiyor. İki seçenek:

**A) Ayrı spike projesi (önerilen — MED'e hiç dokunmaz):**
1. Xcode → File ▸ New ▸ Project ▸ iOS ▸ App. Adı `MEDSpike`, arayüz SwiftUI.
   (İstersen bu repo içinde `spike/MEDSpike/` altına kaydet.)
2. Üretilen `ContentView.swift`/`App.swift`'i sil, bu klasördeki dört dosyayı
   (`SpikeApp.swift`, `SpikeContentView.swift`, `ContainerStore.swift`,
   `PencilPDFReader.swift`) hedefe ekle.
3. Hedef cihaz: bir iPad simülatörü (ya da kendi iPad'in). Çalıştır.

**B) MED hedefini çok-platformlu yap:** MED target ▸ General ▸ Supported
Destinations ▸ **+ iPad** ekle. Daha gerçekçi ama MED'in macOS-only kodu
(AppKit) iOS'ta derlenmeyeceği için bu ancak planın Faz 1'inde mantıklı.
Spike için (A) daha temiz.

> Not: Gerçek "akıcılık" testi için simülatör yeter ama **kalem hissi** ancak
> gerçek iPad + Apple Pencil'da tam anlaşılır.
