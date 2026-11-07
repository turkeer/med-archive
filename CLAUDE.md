# CLAUDE.md — MED için yönerge

Bu dosya, yeni bir sohbetin tüm kodu okumadan projeyi kavraması içindir.
İhtiyaç duydukça ilgili dosyayı aç; her şeyi baştan okuma.

## Uygulama nedir
MED, bir tıp öğrencisinin kendi ders materyallerini (çoğunlukla PDF slayt)
toplayıp organize ettiği, içinde arama yaptığı ve çalışırken yanında başvuru
kaynağı (OpenStax Anatomy & Physiology 2e atlası) bulundurduğu **yerel bir
macOS + iPadOS uygulaması**. SwiftUI + SwiftData. **Tek kod tabanı:** iki platform
aynı çekirdeği paylaşır, platforma özel kabuk `#if os(macOS)` / `#if os(iOS)`
(ya da `#if canImport(AppKit/UIKit)`) ile ayrılır. Tamamen çevrimdışı, tek
kullanıcı; hiçbir veri buluta gitmez. Arayüz Türkçe ve İngilizce (`L.pick`).
Asıl hedef giderek iPad (bkz. "iPad uyarlaması" ve `docs/ipad-uyarlama-plani.md`).

## Derleme ve test
```bash
xcodebuild -scheme MED -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```
```bash
xcodebuild -scheme MED -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```
```bash
xcodebuild -scheme MED -destination 'platform=macOS' test
```
- **Her değişiklikten sonra İKİ platformu da derle** (macOS + iOS). Biri için
  yazılan kod (ör. AppKit) diğerini kırabilir; `#if os` ayrımı doğru mu kontrol et.
- **Proje `PBXFileSystemSynchronizedRootGroup` kullanır:** `MED/` altına eklenen
  yeni `.swift` dosyaları otomatik derlemeye girer. **`.pbxproj` elle düzenleme**
  (hedef/destination/Info.plist ayarları kullanıcıya Xcode'da yaptırılır).
- **SourceKit'in tek-dosya tanılamaları yanıltıcıdır.** Aynı modüldeki tipler için
  sık sık "Cannot find X in scope" der; bunlar **yanlış pozitif**. Tek doğru
  otorite `xcodebuild`; başarıyla derleniyorsa sorun yok.

## Mimari — temel fikirler
- **Merkezde `Lecture` (ders oturumu).** Her şey ona asılı: `Course`,
  `Instructor`, `Committee`, `Tag`, `LectureFile`, `PastExam`.
- **Dosya modeli platforma göre değişir.**
  - **macOS:** sandbox'sız, dosyalar kopyalanmaz **işaret edilir**; kullanıcı bir
    kök klasör seçer, `LectureFile.relativePath` o klasöre görelidir (dışıysa
    mutlak, `/` ile).
  - **iOS:** sandbox zorunlu; dosyalar uygulamanın konteynerine **kopyalanır**.
    Kök her zaman `Documents` (bkz. `StoreLocation`/`LibraryRoot` `#if os(iOS)`).
    `FileAttaching` iOS'ta `library.prepareForAttach` ile kopyalar. Çözümleme yine
    `LectureFile.url(root:)` = kök + relativePath.
- **"Konu" kayıttan üstte.** Bir konu birden çok ders saatine/güne yayılabilir;
  bunlar slaytlarını ve "çalışıldı" durumunu paylaşır. Aynı gün otomatik, farklı
  gün elle (`Lecture.topicLinkID`) gruplanır. Tüm gruplama mantığı
  `LectureGrouping` içinde — "slayt var mı / çalışıldı mı / slaytsız mı"
  sorularını hep buradan geçir, kayıt kayıt değil.
- **Servisler `@Observable @MainActor` sınıflar**, `MEDApp`'te `@State` olarak
  tutulup `.environment()` ile enjekte edilir: `LibraryRoot`, `SlideIndex`,
  `QueryAssistant`, `GlossaryModel`, `ReferenceLibrary`. `AppNavigation` ise
  `ContentView`'da oluşturulur ve ekranlar arası seçim/çapraz gezinmeyi tutar.
- **Üç sütun:** `SidebarView` → bölüme göre liste → detay. Dağıtım `ContentView`.

## Dizin haritası (MED/)
- `MEDApp.swift` — uygulama girişi, ModelContainer, servis enjeksiyonu, menüler.
- `Models/` — SwiftData modelleri. `LectureFormat` (teorik/pratik) bir enum.
  Yeni opsiyonel alanlar migration-güvenli: SwiftData eski satırları NULL okur,
  bu yüzden **Codable enum'ları non-optional ekleme** (çöker); `Lecture.formatRaw`
  yorumuna bak.
- `Support/Domain/` — saf mantık (view'sız). Önemliler:
  - `LectureGrouping` — konu gruplama, çalışıldı/slayt muafiyeti.
  - `SearchText` — Türkçeye duyarlı metin katlama (Yunan harfleri geçer). Arama
    eşleşmeleri hep buradan.
  - `DefinitionExtractor` — slayttan regex ile terim–tanım adayı çıkarımı.
  - `LessonSlot`/`DayTimetable`/`*Grid` — ders saati düzeni ve takvim ızgaraları.
  - `CommitteeIntersection`, `LectureSearch`, `LectureFilter`, `TermCasing`.
- `Support/Storage/` — kalıcılık ve ağır indeksler:
  - `SlideIndex` — kök altındaki tüm PDF'leri sayfa sayfa indeksler (görüntü
    sayfalar için OCR). Slayt araması bunun üzerinde (bellek-içi, hızlı).
  - `GlossaryModel` — sözlük: desen adayları + opsiyonel cihaz-içi Apple modeli
    (kabul/ret/çıkarım) + kullanıcı keep/hide; `definitions(matching:in:)` terim
    arama için.
  - `ReferenceLibrary` — atlas: indirme (OpenStax'ten, resumable), yerel indeks;
    sayfa metni, içindekiler (ünite→bölüm), figürler, Key Terms sözlüğü.
    Key Terms CGPDF içerik akışı + ToUnicode ile okunur (kalın terim / ince
    tanım ayrımı, Yunan harfleri korunur).
  - `StoreLocation` (depo yolu; macOS'ta App Support/MED, iOS'ta `Documents`.
    `Reference/` alt klasörü), `StoreBackup`, `ArchiveExport` (JSON),
    `ContainerCleanup` (iOS: kayda bağlı olmayan öksüz dosyaları açılışta siler;
    **boş depoda hiçbir şey silmez** — göç güvenliği), `ModelContext+*`.
- `Support/Files/` — `LibraryRoot` (iOS: `prepareForAttach` kopyalar,
  `organizeDroppedFiles` Finder köküne bırakılan göç dosyalarını Library'ye taşır),
  `FolderScan`, `FileAttaching`, `FileHealth`, dosya adlandırma.
- `Support/Plumbing/` — `AppNavigation`, `CommandPalette` (⌘K hızlı git),
  `Localization` (`L.pick`/`L.*`), `Palette`/`Color+Hex`, `PlatformStyle`
  (`linkButtonStyle()` — macOS `.link`, iOS `.borderless`), `AboutPanel` (macOS).
- `Views/` — ekranlar. Bölümler: `Workspace/`, `Calendar/`,
  `Lectures/` (Konular; `LectureFilesSection` dosya ekleme + "slaytı yok" +
  "uygulamada oku"), `Slides/` (`SlideSearchView`; `SlidePageDetail` = okuyucu —
  macOS: NSView tabanlı `PDFReaderController`; **iOS: PencilKit okuyucu**
  (`SlidePencilReader`, overlay-provider + `.pencilOnly` + Çiz/Seç modu + OCR'lı
  terim seçimi); `TermLookupPopover` ayrı dosyada, **paylaşımlı**), `Glossary/`,
  `Reference/` (atlas), `Records/`, `Scan/` (macOS-only), `Components/`,
  `CommandPaletteView`, `AppSettingsSheet` (iOS ayarlar/dil), `SidebarView`,
  `SettingsView` (macOS Settings sahnesi), `ContentView`.
- `spike/` — Faz 0 fizibilite denemesi (ayrı iOS hedefi, xcodegen). Üretim değil.

## iPad (iOS) uyarlaması
- **Dal:** iş `ipad` dalında. Plan ve bulgular: `docs/ipad-uyarlama-plani.md`.
- **Platform ayrımı:** AppKit'e dayanan her şey `#if os(macOS)` ile sarılı; iOS
  karşılığı verildi (StoreBackup→UIApplication, TermCasing→UITextChecker,
  `.buttonStyle(.link)`→`linkButtonStyle()` vb.). Settings sahnesi, About paneli,
  "Finder'da göster", JSON/PDF dışa aktarma, klasör tarama **macOS-only**.
- **Veri aynı:** modeller, domain, OCR (Vision), AI (FoundationModels), arama,
  sözlük hepsi paylaşımlı — iki platformda birebir çalışır. AI yalnızca Apple
  Intelligence destekli cihazda (opsiyonel; yoksa regex `DefinitionExtractor`).
- **Mac'ten göç:** `Documents` dosya paylaşımına açık (Info.plist:
  UIFileSharingEnabled + LSSupportsOpeningDocumentsInPlace). Kullanıcı Finder'dan
  `MED.store`(+wal/shm), `Index/` (özellikle `definitions.json` = sözlüğün pahalı
  AI işi, **terime göre** anahtarlı → taşınabilir) ve arşiv klasörlerini MED
  köküne bırakır; `organizeDroppedFiles` arşivi Library'ye taşır. Göreli yollar
  birebir çözülür (tüm dosyalar tek kök altında, göreli).
- **iOS okuyucu (`SlidePencilReader`):** `PDFView` + `PDFPageOverlayViewProvider`
  (sağlayıcı **belgeden ÖNCE** atanmalı, yoksa tetiklenmez) → sayfa-başı
  `PKCanvasView`. `.pencilOnly`: parmak gezer/zoomlar, kalem çizer. Çizimler
  `Documents/Ink/<göreli-yol>/<sayfa>.drawing` (tam yola göre, çakışmasız); özgün
  PDF'e dokunulmaz. Çiz/Seç modu: Seç'te tuval kapanır, parmakla terim seçilir
  (tek dokunuş = kelime; kutu çiz = bölge/çok-kelime), metin katmanı yoksa sayfa
  **anında OCR'lanır**. Terim → `TermLookupPopover` (sözlük + atlas).
- **Atlas iOS'ta:** aynı `ReferenceLibrary` indirir; ya iPad'de indir ya Mac'teki
  `Reference/` klasörünü kopyala (yola bağlı değil, indeks de gelir).

## Önemli kurallar / tuzaklar
- **Yerel/gizlilikçi çizgiyi koru.** Bulut servisi, harici AI çağrısı, telemetri
  ekleme. Yapay zekâ varsa cihaz-içi (Apple Intelligence) ve opsiyonel olmalı.
- **Atlas lisansı CC BY-NC-SA:** uygulama kitaptan **hiçbir şey dağıtmaz**;
  kullanıcı PDF'i indirir, yerelde indekslenir. Atlas içeriğini paketleyen/
  dışa aktaran özellik **ekleme**.
- **İndeks şeması değişirse cache sürümünü yükselt** (`ReferenceLibrary.Cache
  .version` gibi), yoksa eski cache yanlış okunur / çökebilir.
- **Yunan harfleri (β, α...) tıpta önemli:** hem çıkarımda hem arama/gösterimde
  bozulmamalı. Değişiklik yaparken bunu gözet.
- UI metni daima `L.pick("tr", "en")`. Yorum yoğunluğu ve üslup çevre koda uysun
  (bu kod bol açıklayıcı yorum içerir — "neden" anlatır).

## Git
- **Kullanıcının açık onayı olmadan hiçbir git yazma işlemi yapma**
  (`add/commit/push/rebase/reset/checkout/merge/branch`). Sadece okuma serbest.
  Her yazma için ayrı ve açık onay gerekir (global kural).
- Commit mesajları Türkçe. Commit sonuna şu satır eklenir:
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
- **Dallar:** iPad işi `ipad` dalında (güncel çalışma burada). Çalışan saf macOS
  sürümü `claude/gracious-hypatia-7j2vla` dalında ve `mac-stable` etiketinde sabit.
