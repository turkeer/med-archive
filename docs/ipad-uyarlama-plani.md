# MED — iPad Uyarlama Planı

> Durum: taslak / yol haritası · 2026-11-06
> Bu belge "nasıl yaparız"ı anlatır, "yapılır mı"yı değil — o soru tartışıldı ve cevabı: evet, değer.

---

## 1. Amaç ve kapsam

**Amaç.** MED'i iPad'de, kendi kullanımım için çalışır hale getirmek. İki temel kazanç:

1. **Apple Pencil ile çalışma.** Slaytları/PDF'leri uygulamanın *içinde* okuyup üzerine kalemle yazmak, işaretlemek — şu an Notability'de yaptığım ama MED'in zekasından (arama, sözlük, atlas, organizasyon) kopuk olan şey.
2. **Doğal platform.** Tıp öğrencilerinin neredeyse tamamı Mac değil iPad kullanıyor. iPad'de sorunsuz çalışan bir MED, Mac sürümünü benim için gereksiz bırakır.

**Birincil hedef kullanıcı: ben.** Önce kendim indirip kullanacağım. Faydalı olursa *sonra* paylaşmak/yayınlamak gündeme gelir — ama bu plan onun için efor harcamaz, yalnızca kapıyı kapatmaz.

### Hedef olmayanlar (bilinçli dışarıda)
- **Notability'yi yenmek.** Hedef "yaşanabilir, seni yormayan" bir okuma+not deneyimi; on yıllık ergonomi cilası değil. Kriter: *gereksizleştir*, *yenme*.
- **Mac ↔ iPad senkronu.** iPad tek başına, kendi içinde tam. CloudKit yok, cihazlar-arası dosya/etiket paylaşımı yok.
- **App Store / kitleye hazırlık.** İnceleme süreci, gizlilik etiketleri, A-serisi (AI'sız) baz iPad'ler için özel mühendislik — hepsi "beğenirsem, sonra" kutusunda. Şimdi sıfır.
- **Mac sürümüyle kod paylaşımında ödün.** Mac'i dondurabiliriz/bırakabiliriz; iPad'i Mac'e uydurmaya çalışıp iki-platform karmaşıklığı taşımayacağız.

---

## 2. Stratejik yaklaşım

### 2.1 Tek kod tabanı, iPad-öncelikli
Xcode projesine **iOS/iPadOS hedefi** eklenir (multiplatform SwiftUI app). Mac Catalyst **değil** — o iPad→Mac yönü içindir, bize ters. Çekirdek kod (modeller + saf mantık + indeksler + AI) paylaşılır; platforma özel kabuk `#if os(iOS)` / `#if os(macOS)` ile ayrılır.

Mac bırakılacak olsa bile bu yapı mantıklı: paylaşılan çekirdek iPad uygulamasının **temeli**, Mac'e özgü dosyalar ise yeniden yazılacak **kabuk**.

### 2.2 Ne paylaşılır, ne platforma özel

| Katman | Durum | Not |
|---|---|---|
| `Models/` (SwiftData) | ✅ Paylaşılır | Değişiklik yok |
| `Support/Domain/` (LectureGrouping, SearchText, DefinitionExtractor, takvim ızgaraları, LectureFilter…) | ✅ Paylaşılır | Saf Swift. `TermCasing`, `GlossaryExport` zaten `#if canImport(AppKit)` korumalı |
| `SlideIndex` (Vision OCR + PDFKit) | ✅ Paylaşılır | Vision iOS'ta birebir aynı |
| `GlossaryModel`, `QueryAssistant` (FoundationModels) | ✅ Paylaşılır | Aynı framework; cihaz destekliyse çalışır (§3.3) |
| `ReferenceLibrary` (atlas indirme/indeks) | ⚠️ Küçük uyarlama | `import AppKit` sebebini temizle (muhtemelen renk/görsel); indirme mantığı korunur |
| `LibraryRoot`, `FolderScan`, `FileAttaching`, `StoreLocation` | 🔁 iOS varyantı | Dosya modeli değişiyor (§3.1) |
| AppKit tutkalı (~8 dosya) | 🔁 iOS karşılığı | Dosya-dosya envanter §6 |
| SwiftUI ekranları (`Views/`) | 🔁 Dokunma cilası | NavigationSplitView taşınır; hover/sağ-tık/link butonları uyarlanır |
| PDF okuyucu (`SlidePageDetail`'deki `PDFPageView`) | 🔁 UIKit + Pencil | NSViewRepresentable → UIViewRepresentable; Pencil katmanı burada (§5) |

---

## 3. Temel teknik kararlar

### 3.1 Dosya modeli: konteyner-sahipli
**Mac:** sandbox'sız, dış klasöre referans, sıfır-kopya, `relativePath` keyfi bir köke göreli.
**iPad:** uygulama **kendi konteynerine** dosyaları içe alır (kopyalar). Sebep: iOS sandbox zorunlu; konteyner-içi dosyaya düz yolla erişilir — security-scoped bookmark, `startAccessingSecurityScopedResource`, bayat bookmark yönetimi **hiç yok.**

Sonuçlar:
- `LectureFile.relativePath` artık **her zaman** konteynerin `Documents/` klasörüne göreli. Mac'teki "dışarıdaysa `/` ile mutlak" istisnası iPad'de **ortadan kalkıyor** — model basitleşiyor.
- İçe alma: `UIDocumentPicker` (çoklu dosya / klasör içeriği), "MED'de Aç" paylaşım eylemi, Files'tan sürükle-bırak.
- Takas: disk ikilenmesi (dosya hem Files/iCloud'da hem konteynerde olabilir). Kabul edilebilir; iPad depolaması yeter.

### 3.2 Depo (SwiftData store)
`StoreLocation` zaten `URL.applicationSupportDirectory` kullanıyor — iOS'ta bu **zaten konteyner-içi.** Mac'teki veri-kaybı gerekçesi (başka süreçlerin `default.store`'u açması) iOS'ta sandbox sayesinde **kendiliğinden yok.** Yani depo katmanı iOS'ta neredeyse hazır; `Reference/` alt klasörü de aynı mantıkla taşınır.

### 3.3 Minimum OS ve cihaz
- **iPadOS 26+** (FoundationModels için).
- **AI katmanı:** yalnızca Apple Intelligence destekli iPad'lerde (M1+ / A17 Pro). Benim iPad'im destekliyorsa sözlük AI'ı ve arama asistanı **olduğu gibi** çalışır. Desteklemiyorsa regex tabanlı `DefinitionExtractor` yedeği devrede — uygulama zaten bunu opsiyonel kurguluyor, bu zarif düşüş iPad'e aynen taşınıyor.
- **PDF + Pencil:** iPadOS 16+ yeter (overlay provider API'si), ama zaten 26 tabanındayız.

---

## 4. Faz faz yol haritası

### Faz 0 — Fizibilite spike (1–2 gün) 🔬
**Amaç:** iki belirsizliği kanıtlamak. Kod kalitesi değil, "gidilir mi" cevabı önemli.

1. **Dosya içe alma:** iPad simülatöründe `UIDocumentPicker` ile bir PDF seç → konteynere kopyala → `PDFDocument` ile aç. Security-scoped bookmark'sız çalışıyor mu?
2. **Pencil akıcılığı:** ~200 sayfalık (çok mürekkepli) bir desteyi `PDFView` + sayfa-başına `PKCanvasView` (`PDFPageOverlayViewProvider` ile) + `.pencilOnly` ile aç. Parmakla kaydır/zoomla, kalemle yaz — **takılıyor mu?**

**Başarı kriteri:** ikisi de pürüzsüz çalışıyorsa yeşil ışık; geri kalan her şey "bilinen iş." Takılırsa önce performans stratejisini (tembel canvas, görünür-sayfa oluşturma) çözeriz.

> Not: Spike ayrı bir dalda/deneme hedefinde yapılır; üretim koduna karışmaz.

#### Faz 0 — SONUÇ ✅ (2026-11-06, `spike/`)
Gerçek iPad'de (xcodegen ile üretilen ayrı `MEDSpike` iOS hedefi) **yeşil**:
- ✅ **Konteyner içe alma** — dış PDF `UIDocumentPicker` ile `Documents/`'a
  kopyalanıp **security-scoped bookmark olmadan** açılıyor.
- ✅ **Görüntüleme + sayfa çevirme** — `PDFView`, tek-sayfa modunda.
- ✅ **Apple Pencil çizimi** — `PKCanvasView`, Apple'ın kendi araç paletiyle,
  akıcı; sayfaya **hizalı**.
- ✅ **Sayfa-başı kalıcılık** — her sayfanın çizimi `PKDrawing` olarak diske
  yazılıp geri yükleniyor (kapat-aç sonrası yerinde).

**Kritik bulgu:** `PDFPageOverlayViewProvider` (eşzamanlı "parmak gez + kalem
yaz" + otomatik hizalama için Apple'ın resmi API'si) bu ortamda (iPadOS 26 /
Xcode 27) **hiç tetiklenmedi** — `overlayViewFor` çağrılmıyor. Spike bu yüzden
tek-sayfa + tam-boyut tuval + ◀▶ düğmeleriyle çalışıyor (finger-scroll/zoom
yok). Bu bir **fizibilite duvarı değil** (GoodNotes/Notability bunu yapıyor);
Faz 5'in ilk işi bunu çözmek. → §5'e bak.

### Faz 1 — İskele (çekirdek iPad'de derlenip açılsın)
- Multiplatform iOS hedefi ekle; paylaşılan çekirdeği hedefe dahil et.
- `#if os(iOS)` ile derlemeyi engelleyen AppKit importlarını geçici olarak izole et (gövdeleri boş/stub).
- `StoreLocation` + `ModelContainer` iOS'ta açılsın; boş bir `ContentView` (sidebar + placeholder) iPad simülatöründe çalışsın.
- **Bitti göstergesi:** iPad'de uygulama açılıyor, üç sütun görünüyor, çöküyor değil.

### Faz 2 — Dosya katmanı
- `LibraryRoot` iOS varyantı: "kök = konteyner `Documents/`", dış klasör seçimi yok.
- İçe alma akışı: `UIDocumentPicker` tabanlı "dosya ekle" + çoklu seçim; `FileAttaching`'in iOS yolu dosyayı konteynere kopyalayıp `relativePath` üretir.
- `FolderScan` iOS: konteyner `Documents/` altını tarar (kök-dışı mantığına gerek yok).
- `StoreLocation` + `Reference/` alt klasörü iOS'ta doğrula.
- **Bitti göstergesi:** bir slaytı içe alıp bir derse bağlayabiliyorum; `SlideIndex` onu OCR'layıp aramada buluyor.

### Faz 3 — AppKit tutkalının iOS karşılığı
§6'daki dosya-dosya envanter uygulanır. Özet:
- Dışa aktarma (`ArchiveExport`, `GlossaryExport`): `NSSavePanel` → paylaşım sayfası / `UIDocumentPicker` export.
- "Finder'da göster" (`FileRow`, `SettingsView`, `SlidePageDetail`, `StoreFailureView`): iOS'ta karşılığı yok → `QLPreviewController` ile önizleme veya paylaşım sayfası; çoğu yerde butonu iOS'ta gizle.
- `AboutPanel`: standart panel → uygulama-içi "Hakkında" ekranı.
- `StoreBackup`: `NSApplication.didResignActive` → `UIApplication` eşdeğeri (`willResignActiveNotification`).
- Ayarlar: macOS `Settings` sahnesi iOS'ta yok → sidebar'da/araç çubuğunda uygulama-içi ayar ekranı.
- `Palette`/renk: `NSColor` köprüsü → çapraz-platform (`UIColor`/`Color`).
- Menüler/kısayollar (`⌘E`, `⌘K`): iOS'ta menü çubuğu yok; donanım klavyede kısayol korunur, ama ⌘K'ye **görünür bir giriş** (araç çubuğu düğmesi) eklenir ki klavyesiz de erişilsin.

### Faz 4 — Dokunma cilası
- NavigationSplitView iPad davranışı (portre/manzara, sidebar daralt/genişlet).
- `hover` → kaldır; sağ-tık bağlam menüleri → uzun bas; `.buttonStyle(.link)` → dokunma hedefli buton.
- Dokunma hedefleri, boşluklar, liste satır yükseklikleri iPad'e göre.
- **Bitti göstergesi:** tüm mevcut ekranlar (Konular, Takvim, Arama, Sözlük, Atlas, Kayıtlar, Çalışma alanı) iPad'de kullanılabilir.

### Faz 5 — Pencil PDF okuyucu ⭐ (asıl ödül)
Mevcut `PDFPageView: NSViewRepresentable` → `UIViewRepresentable`. Çekirdek PDFKit mantığı (seçim, `findString`, sayfa senkronu, `PDFReaderController`) **büyük ölçüde aynı** — PDFView/PDFSelection/PDFPage API'si iOS'ta birebir.

Üstüne Pencil:
- UIKit `PDFView` + `PDFPageOverlayViewProvider` (her sayfaya bir `PKCanvasView` overlay'i, zoom/scroll'da hizalı).
- `canvasView.drawingPolicy = .pencilOnly` → **parmak = gez, kalem = yaz.**
- `PKToolPicker` ile araç paleti.
- Kalıcılık: her sayfanın çizimi `PKDrawing.dataRepresentation()` → SwiftData'da sayfa kimliğine (`dosya yolu + sayfa no`, zaten `SlidePageSelection` taşıyor) bağlı blob. Büyük destelerde tembel yükle.
- **Terim arama korunur:** seçim → "Ara" popover'ı iOS'ta da çalışır (aynı seçim mantığı). Bu, okuyucunun MED'e özgü değeri.
- **Bitti göstergesi:** bir slaytı aç, parmakla gez, kalemle yaz, bir terimi seçip sözlük/atlas'a bak, kapat-aç → notlar yerinde.

### Faz 6 — Yaratıcı katman (sonraya, ama bu mimari onu açar)
Çizim katmanı kurulunca üstüne biner:
- **Vurgu/işaretleme** (fosforlu, serbest çizim) — Faz 5 ile zaten büyük ölçüde geliyor.
- **Otomatik etiket maskeleme:** `SlideIndex`'in OCR konum verisiyle anatomi şemasındaki yazıları tek tek kapat → "yapıyı adlandır" alıştırması. Uygulamanın en ayırt edici potansiyeli.
- **Örtük metin (cloze):** vurgula → gizle → kart. `DefinitionExtractor` ile beslenir.
- **Pin quiz:** figür üstüne nokta koy, adlandır, test et.

> Faz 6 ayrı planlanacak; buraya sadece "mimari buna hazır" diye konuyor.

---

## 5. PDF + Pencil entegrasyonu — teknik özet

**Kanıtlanan (Faz 0):** PencilKit mürekkebi akıcı ve kaliteli (Apple Notes'un
motoru); `PKCanvasView` PDF üstüne çiziyor; sayfa-başı kalıcılık çalışıyor.

**Çözülecek (Faz 5'in ilk işi): eşzamanlı "parmak gez + kalem yaz" + hizalama.**
Apple'ın bunun için olan resmi API'si `PDFPageOverlayViewProvider`, Faz 0
ortamında (iPadOS 26 / Xcode 27) **tetiklenmedi**. Denenecek yollar, sırayla:

1. **Sağlayıcıyı neden sessiz kaldığını kazı** — doküman/sağlayıcı atama sırası,
   gerekli bir `layoutDocumentView()` tetiği, display-mode gereksinimi, ya da
   SDK 27'ye özgü bir davranış. En temiz çözüm bu; çalışırsa her şey (finger-
   scroll + pencil-draw + hizalama + kalıcılık) bedava gelir.
2. **Tuvali PDFView'in iç kaydırma katmanına gömmek** — `PKCanvasView`'ı
   `PDFView`'in iç belge/scroll görünümüne alt-görünüm olarak ekle, kendi
   kaydırmasını kapat; parmak pan'i üst scroll view'e, kalem tuvale gider.
   (İç hiyerarşiye eriştiği için kırılgan; dikkatli yapılmalı.)
3. **Elle jest yönlendirme** — tam-boyut tuval üstte (`.pencilOnly`), üstüne
   yalnızca parmak için `UIPan/UIPinch` tanıyıcılar ekleyip PDFView'i elle
   kaydır/zoomla. Kalem PencilKit'e, parmak bize gider.
4. **Son çare — "Gez/Yaz" modu:** kesin çalışır (spike'ta da gördük: tuval
   etkileşimi açık=yaz, kapalı=gez), ama "modsuz sihir" değil.

**Not:** Büyük deste akıcılığı Faz 0'da sorun çıkarmadı; asıl açık madde bu
ergonomi.

---

## 6. Dosya-dosya göç envanteri

| Dosya | Bağımlılık | iOS'ta yapılacak | Boyut |
|---|---|---|---|
| `Support/Storage/StoreLocation.swift` | applicationSupportDirectory | Neredeyse hazır; iOS'ta konteyner-içi | XS |
| `Support/Storage/ArchiveExport.swift` | `NSSavePanel` | Paylaşım sayfası / `UIDocumentPicker` export | S |
| `Support/Storage/StoreBackup.swift` | `NSApplication.didResignActive` | `UIApplication.willResignActiveNotification` | XS |
| `Support/Storage/ReferenceLibrary.swift` | `import AppKit` | AppKit sebebini temizle (renk/görsel), indirme korunur | S |
| `Support/Plumbing/AboutPanel.swift` | `orderFrontStandardAboutPanel` | Uygulama-içi "Hakkında" ekranı | S |
| `Support/Plumbing/Palette.swift` | `NSColor` (yorum/köprü) | Çapraz-platform renk | XS |
| `Support/Domain/TermCasing.swift` | `#if canImport(AppKit)` | Zaten korumalı — iOS şubesi doğrula | XS |
| `Support/Domain/GlossaryExport.swift` | `#if canImport(AppKit)` (NSColor/NSFont PDF) | Zaten korumalı; iOS PDF çizimi (UIKit/CoreGraphics) | M |
| `Support/Files/LibraryRoot.swift` | dış klasör yolu | Konteyner-sahipli model | M |
| `Support/Files/FolderScan.swift` | dış klasör tarama | Konteyner `Documents/` tarama | S |
| `Support/Files/FileAttaching.swift` | referans | İçe alma (kopyala) + relativePath | M |
| `Views/StoreFailureView.swift` | `NSWorkspace` | "Finder'da göster"i gizle/ önizleme | XS |
| `Views/SettingsView.swift` | `NSWorkspace`, Settings sahnesi | Uygulama-içi ayarlar | M |
| `Views/Components/FileRow.swift` | `NSWorkspace.open/reveal` | `QLPreviewController` / paylaşım | S |
| `Views/Slides/SlidePageDetail.swift` | `NSViewRepresentable`, `NSWorkspace`, PDFKit | `UIViewRepresentable` + Pencil (Faz 5) | L |
| `MEDApp.swift` | `.commands`, `Settings` sahnesi | iOS sahne yapısı, kısayollar | M |

Boyut: XS=dakikalar, S=saatler, M=yarım-bir gün, L=birkaç gün.

---

## 7. Riskler ve azaltma

| Risk | Olasılık | Azaltma |
|---|---|---|
| Büyük destede Pencil/scroll takılması | Orta | Faz 0 spike ölçer; tembel canvas, görünür-sayfa oluşturma |
| Konteyner disk şişmesi | Düşük-orta | iPad depolaması yeter; ileride "içe aktarıldı, kaynağı sil" seçeneği |
| AI'ın cihazda olmaması | Düşük (kendi M-serisi iPad'im) | Regex yedeği zaten var, opsiyonel kurgu taşınıyor |
| İki-platform bakım yükü | Düşük | Mac dondurulabilir/bırakılabilir; iPad tek öncelik |
| Arka plan OCR indeksleme kısıtı | Orta | Ön planda indeksle veya `BGProcessingTask`, parçalı |
| Toplu içe alma ergonomisi | Düşük | `UIDocumentPicker` çoklu/klasör içe alma |

---

## 8. "Bitti" ne demek (v1 kabul kriteri)
Kendi iPad'imde, Mac'e ihtiyaç duymadan:
1. Slaytlarımı içe alıp derslere/konulara bağlayabiliyorum.
2. Tüm slaytlarda OCR'lı arama + sözlük + atlas çalışıyor (AI destekli cihazda AI'lı).
3. Bir slaytı açıp **Apple Pencil ile üzerine yazabiliyorum**, parmakla rahatça geziyorum, notlarım kalıcı.
4. Seçtiğim terimi sözlük/atlas'ta aratabiliyorum.
5. Takvim, kayıtlar, çalışma alanı, Cmd+K — hepsi dokunmayla kullanılabilir.

Bu beş madde sağlanınca Notability + MED(Mac) ikilisi benim için tek bir iPad uygulamasına iniyor.

---

## 9. İlk adım
**Faz 0 spike.** Başka hiçbir şeye başlamadan önce o iki belirsizliği (konteyner içe alma + Pencil akıcılığı) kanıtla. Yeşilse bu plan uygulanır; değilse önce performans stratejisi netleşir.
