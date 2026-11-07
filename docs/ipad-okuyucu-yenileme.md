# iPad okuyucu arayüz yenilemesi — uygulama planı

> Amaç: iOS slayt okuyucusunu (PDF görüntüleme + PencilKit not alma) Notability
> hissine yaklaştırmak: sade, net, modern; girişte karmakarışık değil, sayfa
> baskın, kontroller gerekince belirip gizlenir. **Çizim motorunu yazmıyoruz** —
> Apple PencilKit (PKCanvasView) tüm çizimi/basıncı/geri-alı/saklamayı yapmaya
> devam eder; biz yalnızca stok `PKToolPicker`'ı gizleyip kendi araç çubuğumuzu
> çizer, `canvas.tool`'u (`PKInkingTool`/`PKEraserTool`) kendimiz ayarlarız.

Görsel referans: `docs/ipad-okuyucu-mockup.html` (tarayıcıda aç).

---

## Mevcut durum (başlangıç noktası)

- iOS okuyucu: `MED/Views/Slides/SlidePageDetail.swift`
  - `SlidePageDetail` (iOS sürümü, ~satır 643): üstte **Çiz/Seç** modu `Picker`'ı
    ([satır 674]), Seç modunda "Ara" düğmesi (terim → sözlük/atlas).
  - `SlidePencilReader` (UIViewRepresentable, ~satır 759): `PDFView`
    (`.singlePageContinuous`, arka plan `.systemGray5` [satır 776]) + üstüne
    `PDFPageOverlayViewProvider` ile sayfa-başı `PKCanvasView` overlay.
  - `Coordinator` (~satır 865): `let toolPicker = PKToolPicker()` [satır 869] —
    **STOK Apple paleti = "Notes hissi"nin kaynağı.** `.pencilOnly` [satır 903];
    çizimler her darbede kaydediliyor (`canvasViewDrawingDidChange`, ~1151) →
    `Documents/Ink/<göreli-yol>/<sayfa>.drawing`.
  - Seç modu: metin katmanı varsa oradan, yoksa OCR; tek dokunuş = kelime, kutu =
    bölge/çok-kelime; terim → `TermLookupPopover` (ayrı dosya, paylaşımlı).
- macOS okuyucu AYRI (NSView tabanlı `PDFReaderController`, aynı dosyada
  `#if os(macOS)`), **bu yenileme yalnızca iOS**. macOS'a dokunma.
- macOS tarafı zaten `PDFThumbnailView` kullanıyor (`PDFThumbnailPane`, ~satır
  572) — iOS önizleme rayında bunu örnek al.

---

## Hedef yerleşim (mockup)

- **Sol üst:** sade geri ikonu (yuvarlak material, `chevron.left`/`xmark`) +
  yanında önizleme panelini açan/kapatan ikon (`sidebar`). Yazı yok.
- **Sol:** panel açılınca küçük sayfa önizleme rayı (dikey liste); aktif sayfa
  vurgulu; dokun → o sayfaya git. Tekrar bas → kapanır, sayfa tam genişlik.
- **Sağ alt:** **dikey** sayfa hapı — yukarıdan aşağı: `chevron.up`, açık sayfa
  no, ince yatay ayraç çizgi, toplam sayfa (soluk), `chevron.down`. Sayfa
  değişince/dokununca belirir, okurken gizlenir.
- **Alt orta:** kalem paleti (aşağıda ayrıntı).
- **Sayfaya dokununca** tüm kontroller gizlenir/belirir (tam ekran okuma).
- **Zemin:** beyaz sayfa, ince kenarlık, yumuşak nötr arka plan; sayfa "yüzer"
  (`pdfView.pageShadowsEnabled = true`, arka plan `.systemGray5` yerine nötr).

### Kalem paleti (alt orta)

Soldan sağa:
1. **Kalem ön-ayarları** (çoklu): her biri kendi rengi+kalınlığı olan bir
   `PKInkingTool`. Dokun → o kalemle yaz. **Zaten aktif** olana tekrar dokun →
   üstünde **balon** açılır: renk satırı + kalınlık satırı.
2. Ayraç.
3. **Fosforlu** (`PKInkingTool(.marker)`), **silgi** (`PKEraserTool`), **seçim**
   (lasso, `PKLassoTool`).
4. Ayraç. **Geri al** (`canvas.undoManager?.undo()`).
5. Ayraç. **Sözlük modu** (kitap ikonu) — AKTİFKEN çizim durur, parmakla metin
   seçip aratılır (bugün üstteki "Seç" modunun işi; buraya taşınır, üstteki
   Çiz/Seç `Picker` kalkar). **Ayarlar/düzenle** (dişli) — kalem ön-ayarlarını
   ekle/çıkar/sırala modalı.

### Araç balonları

- **Kalem balonu** (aktif kaleme tekrar dokununca): renk seçimi (birkaç swatch) +
  kalınlık (birkaç preset / slider). Seçim o ön-ayarın `PKInkingTool`'unu günceller.
- **Silgi balonu:** boyut + mod — **Çizgi/nesne** = `PKEraserTool(.vector)` (tüm
  darbeyi siler), **Piksel** = `PKEraserTool(.bitmap)` (gezdiğin yeri siler).

### Ayar modalı (dişli)

Notability tarzı: kalem ön-ayarlarını listele, **ekle** (+), **sil**, **sırala**
(drag), her birinin renk/kalınlığını düzenle. Değişiklikler kalıcı (aşağıya bak).

---

## Kalem ön-ayar modeli ve kalıcılık

- Basit bir `Codable` tip: `PenPreset { id, inkType (.pen/.pencil/.marker),
  colorHex, width }`. Liste `[PenPreset]` + seçili id.
- Kalıcılık: `UserDefaults` (JSON) yeterli — tek kullanıcı, küçük veri. SwiftData'ya
  gerek yok. (Göç/karmaşa istemiyoruz; bu sadece kullanıcı tercihi.)
- Uygulama açılışında yükle; modal/balon değişikliğinde kaydet.
- Bir ön-ayara basınca: `canvas.tool = PKInkingTool(preset.inkType,
  color: UIColor(hex: preset.colorHex), width: preset.width)`.

---

## PencilKit API eşlemesi (motor Apple'da kalır)

| İşlev | API |
|---|---|
| Kalem | `PKInkingTool(.pen, color:, width:)` |
| Fosforlu | `PKInkingTool(.marker, color:, width:)` |
| Silgi (nesne) | `PKEraserTool(.vector)` (+ iOS 16.4+ `width:`) |
| Silgi (piksel) | `PKEraserTool(.bitmap, width:)` |
| Seçim | `PKLassoTool()` |
| Aracı uygula | `canvas.tool = ...` (her sayfa-overlay canvas'ına) |
| Geri al / ileri | `canvas.undoManager?.undo()/redo()` |
| Stok paleti GİZLE | `toolPicker`'ı observer olarak EKLEME; `toolPicker.setVisible(false, forFirstResponder: canvas)` ve kendi UI'ımızı kullan |

Not: birden çok sayfa-overlay canvas'ı var. Seçili aracı, o an görünen/first
responder olan canvas'a uygula; `addOverlayView`'da yeni canvas gelince de aynı
aracı set et (tutarlı kalsın).

---

## Fazlar (önerilen sıra — her faz sonunda İKİ platformu derle)

- **Faz A — Yerleşim/krom (çizime dokunmadan):** sol üst geri ikonu + panel
  toggle, sol önizleme rayı (`PDFThumbnailView`), sağ alt dikey sayfa hapı,
  sayfaya dokununca krom gizle/göster, zemin/gölge rötuşu. Üstteki Çiz/Seç
  `Picker` şimdilik durabilir.
- **Faz B — Özel kalem çubuğu:** stok `PKToolPicker`'ı gizle; tek kalem +
  fosforlu + silgi + seçim + geri-al + araç balonları (kalınlık/renk;
  silgi boyut/mod). Davranış eşdeğeri olunca üstteki paleti tümüyle bırak.
- **Faz C — Çoklu kalem ön-ayarları:** `PenPreset` modeli + kalıcılık; çubukta
  birden çok kalem; aktif kaleme tekrar dokun → balon.
- **Faz D — Ayar modalı:** ön-ayar ekle/sil/sırala/düzenle.
- **Faz E — Sözlük modunu palete taşı:** kitap düğmesi = eski "Seç" modu; üstteki
  Çiz/Seç `Picker` kaldırılır. Mevcut seçim+`TermLookupPopover` mantığı korunur.

İstenirse A+B ilk teslim; C/D/E ardışık.

---

## Tuzaklar / dikkat

- **İki platform:** her değişiklikten sonra macOS + iOS derle. Okuyucu kodu aynı
  dosyada; iOS kısmı `#if os(iOS)`. macOS `PDFReaderController`'a dokunma.
- **Overlay sağlayıcı belgeden ÖNCE atanmalı** (yoksa tetiklenmez) — mevcut kurulum
  bozulmasın.
- `.pencilOnly`: parmak gezer/zoomlar, kalem çizer. Krom dokunma-ile-gizleme bunu
  bozmamalı (parmak dokunuşu PDF'te; çizim kalemde).
- Çizimler bugün `canvasViewDrawingDidChange`'de kaydediliyor; araç/kalem
  değişimi bunu etkilememeli.
- **SourceKit "Cannot find X in scope" yanlış pozitif** — otorite `xcodebuild`.
- `.pbxproj` elle düzenlenmez; yeni `.swift` dosyaları `Views/`/`Support/` altına
  konursa otomatik derlemeye girer (senkronize grup). Yeni kaynak (ikon vs.) SF
  Symbols ile; ekstra asset gerekmez.
- Async köprü kurarsan (ör. balon/modal), continuation'ı **tek sefer** resume et.

---

## Kabul kriterleri

- İki platform da derleniyor; macOS okuyucu değişmemiş.
- PencilKit çizim kalitesi/gecikmesi aynı (stok motordan farksız).
- Çizimler eskisi gibi kalıcı; eski `.drawing` dosyaları okunur.
- Sözlük arama (metin katmanı + OCR) eskisi gibi çalışır.
- Kalem ön-ayarları kalıcı; ekle/sil/sırala çalışır.
- Giriş ekranı sade; kontroller dokununca gizlenir/belirir.

---

## Dosya/entegrasyon noktaları

- Ana dosya: `MED/Views/Slides/SlidePageDetail.swift` (iOS `SlidePencilReader` +
  `Coordinator`). Krom SwiftUI katmanı buranın etrafında.
- Yeni dosyalar (öneri, `MED/Views/Slides/Reader/` altına):
  `ReaderChrome.swift` (üst/alt kontroller), `PenPalette.swift` (çubuk+balonlar),
  `PenPreset.swift` (model+kalıcılık), `PenSettingsSheet.swift` (modal),
  `PageThumbnailRail.swift` (`PDFThumbnailView` sarmalayıcı).
- `TermLookupPopover.swift` ve Seç-modu mantığı korunur, sözlük moduna bağlanır.
