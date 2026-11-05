# CLAUDE.md — MED için yönerge

Bu dosya, yeni bir sohbetin tüm kodu okumadan projeyi kavraması içindir.
İhtiyaç duydukça ilgili dosyayı aç; her şeyi baştan okuma.

## Uygulama nedir
MED, bir tıp öğrencisinin kendi ders materyallerini (çoğunlukla PDF slayt)
toplayıp organize ettiği, içinde arama yaptığı ve çalışırken yanında başvuru
kaynağı (OpenStax Anatomy & Physiology 2e atlası) bulundurduğu **yerel bir macOS
uygulaması**. SwiftUI + SwiftData. Tamamen çevrimdışı, tek kullanıcı; hiçbir veri
buluta gitmez. Arayüz Türkçe ve İngilizce (`L.pick`).

## Derleme ve test
```bash
xcodebuild -scheme MED -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```
```bash
xcodebuild -scheme MED -destination 'platform=macOS' test
```
- **Proje `PBXFileSystemSynchronizedRootGroup` kullanır:** `MED/` altına eklenen
  yeni `.swift` dosyaları otomatik derlemeye girer. **`.pbxproj` elle düzenleme.**
- **SourceKit'in tek-dosya tanılamaları yanıltıcıdır.** Aynı modüldeki tipler için
  sık sık "Cannot find X in scope" der; bunlar **yanlış pozitif**. Tek doğru
  otorite `xcodebuild`; başarıyla derleniyorsa sorun yok.

## Mimari — temel fikirler
- **Merkezde `Lecture` (ders oturumu).** Her şey ona asılı: `Course`,
  `Instructor`, `Committee`, `Tag`, `LectureFile`, `PastExam`.
- **Dosyalar kopyalanmaz, işaret edilir.** Kullanıcı bir kök klasör seçer;
  `LectureFile.relativePath` o klasöre görelidir (klasör dışıysa mutlak, `/` ile).
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
  - `StoreLocation` (depo yolu, `Reference/` alt klasörü), `StoreBackup`,
    `ArchiveExport` (JSON), `ModelContext+*`.
- `Support/Files/` — `LibraryRoot`, `FolderScan`, `FileAttaching`, `FileHealth`,
  dosya adlandırma.
- `Support/Plumbing/` — `AppNavigation`, `Localization` (`L.pick`/`L.*`),
  `Palette`/`Color+Hex`, `AboutPanel`.
- `Views/` — ekranlar. Bölümler: `Workspace/` (çalışma alanı), `Calendar/`,
  `Lectures/` (Konular; `LectureFilesSection` dosya ekleme + "slaytı yok" +
  "uygulamada oku"), `Slides/` (`SlideSearchView`, `SlidePageDetail` = uygulama
  içi PDF okuyucu + terim arama popover'ı + `PDFReaderController`), `Glossary/`,
  `Reference/` (atlas), `Records/` (kurs/akademisyen/komite/etiket + geçmiş
  sınavlar), `Scan/`, `Components/`, `SidebarView`, `SettingsView`, `ContentView`.

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
- Ana/çalışma dalı: `claude/gracious-hypatia-7j2vla`.

## Durum (2026-11-06)
Son eklenenler: uygulama içi slayt okuyucu (canlı sayfa, git/zoom/thumbnail,
eşleşme gezinme), seçili terim için slayt sözlüğü + atlas popover'ı, "slaytı yok"
muafiyeti. Olası sonraki işler için önceliklendirilmiş fikirler konuşuldu
(kurul hız sayacı, fonetik TR↔EN eşleşme, kısaltma/etimoloji çözücü, görüntü
maskeleme, Cmd+K, çok durumlu çalışma takibi).
