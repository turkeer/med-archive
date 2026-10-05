# MED — Ders Takip Uygulaması

macOS için tek kullanıcılı ders arşivi. SwiftUI + SwiftData, hedef macOS 14+.

Tasarım belgesi: [`docs/teknik-tarif.md`](docs/teknik-tarif.md)

## Açmak ve çalıştırmak

```
open MED.xcodeproj
```

Xcode açıldıktan sonra sol üstteki şemanın **MED** ve hedefin **My Mac** olduğundan
emin ol, `Cmd+R` ile çalıştır. Başka bir ayar gerekmiyor.

### Neden Developer hesabı istemiyor

Hedef sadece Mac. Proje `CODE_SIGN_IDENTITY = "-"` ile, yani yerel (ad-hoc) imzayla
derleniyor — kendi makinende süresiz çalışır. Haftalık yeniden imzalama yalnızca
iOS/iPadOS cihazlarına kurulumda gerekiyor, burada öyle bir şey yok.

### App Sandbox kapalı

Uygulama App Store'a gönderilmeyeceği için sandbox açılmadı. Bunun tek sebebi
sadelik: sandbox altında iCloud klasörüne erişmek güvenlik kapsamlı yer imi
(security-scoped bookmark) makinesi gerektiriyor, kapalıyken düz dosya yolu
yetiyor. 5. aşamada kesinleşir; model şimdiden iki yola da uygun.

## Veri modeli

Merkezde `Lecture` var, diğer dört varlık ona bağlı.

| Varlık | Not |
| --- | --- |
| `Lecture` | Saatler `startMinutes` / `endMinutes` olarak, gece yarısından itibaren dakika cinsinden tutulur. `date` yalnızca günü taşır. |
| `Instructor` | Akademik unvan alanı `titleText` adını taşıyor; `Lecture.title` ile karışmasın. |
| `Committee` | `colorHex` takvimde günleri işaretlemek için. |
| `Tag` | `name` tekil (`@Attribute(.unique)`) — aynı konu iki yazımla birikmez. |
| `LectureFile` | Dosya yolu `relativePath`'te; `bookmarkData` yalnızca sandbox açılırsa gerekir. |

Silme kuralları:

- Akademisyen veya komite silinirse dersler **silinmez**, alan boşalır (`.nullify`).
- Ders silinirse `LectureFile` kayıtları silinir (`.cascade`), **diskteki dosyaya dokunulmaz**.

## Dosyaların yeri

PDF'ler uygulamanın içine kopyalanmaz, iCloud Drive'da kalır:

```
~/Library/Mobile Documents/com~apple~CloudDocs/MED/
  Komite I/
    Biyofizik/
      2026-10-01 | Basic Principles in Biophysics.pdf
```

## Aşamalar

- [x] **1. Veri modeli ve ders listesi** — beş `@Model`, `ModelContainer`, liste + ekleme formu
- [ ] 2. Ders detayı ve düzenleme, tamamlamalı açılır listeler
- [ ] 3. Akademisyen / komite / etiket detay ekranları
- [ ] 4. Aylık takvim
- [ ] 5. Dosya bağlama ve QuickLook
- [ ] 6. Otomatik klasör tarama ve eşleştirme
- [ ] 7. Arama ve JSON dışa aktarma

## Dosya düzeni

```
MED/
  MEDApp.swift          @main, ModelContainer kurulumu
  Models/               Lecture, Instructor, Committee, Tag, LectureFile
  Views/                ContentView, LectureListView, LectureFormView
  Support/              TimeOfDay (dakika↔Date), Color+Hex
```
