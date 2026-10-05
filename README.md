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

Merkezde `Lecture` var — tek bir oturum. Diğer beş varlık ona bağlanıyor.

| Varlık | Ne | Not |
| --- | --- | --- |
| `Lecture` | Bir oturum | `title` o günün **konusu**. Saatler `startMinutes` / `endMinutes` olarak gece yarısından itibaren dakika cinsinden; `date` yalnızca günü taşır. |
| `Course` | Tekrar eden ders — Anatomi, Biyofizik | Diskteki ders klasörünün karşılığı. Bilerek komiteye bağlı **değil**: aynı ders birden çok komitede geçiyor. |
| `Committee` | Komite I, II… | `colorHex` takvimde günleri işaretlemek için. |
| `Instructor` | Akademisyen | Akademik unvan alanının adı `titleText` — `Lecture.title` ile karışmasın. |
| `Tag` | Serbest etiket | Oturumları **enine kesen** konular: membran, sınavda çıktı. Yapısal seviye `Course`, serbest etiket `Tag`. `name` tekil (`@Attribute(.unique)`). |
| `LectureFile` | Diskteki bir dosyaya işaretçi | Yol `relativePath`'te; `bookmarkData` yalnızca sandbox açılırsa gerekir. |

`Course`, `Committee` ve `Instructor` oturumda tekil ve boş bırakılabilir.
`Tag` çoklu ve çift yönlü. `LectureFile` çoklu ve tek bir oturuma ait.

Silme kuralları:

- `Course`, `Instructor` veya `Committee` silinirse **oturumlar silinmez**, ilgili alan boşalır (`.nullify`).
- Bir oturum silinirse `LectureFile` kayıtları silinir (`.cascade`), **diskteki dosyaya dokunulmaz**.

## Kavram sırası

Diskteki klasör hiyerarşisi veri modeliyle birebir örtüşüyor:

```
Komite I  /  Biyofizik  /  2026-10-01 | Basic Principles in Biophysics.pdf
Committee     Course                    Lecture.date   Lecture.title (konu)
```

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
- [x] **2. Ders detayı ve düzenleme** — iki kolonlu düzen, canlı düzenleme, tamamlamalı alanlar
- [ ] 3. Akademisyen / komite / etiket detay ekranları
- [ ] 4. Aylık takvim
- [ ] 5. Dosya bağlama ve QuickLook
- [ ] 6. Otomatik klasör tarama ve eşleştirme
- [ ] 7. Arama ve JSON dışa aktarma

## Dosya düzeni

```
MED/
  MEDApp.swift          @main, ModelContainer kurulumu
  Models/               Lecture, Course, Instructor, Committee, Tag, LectureFile
  Views/
    ContentView         NavigationSplitView kabuğu, seçim durumu
    LectureListView     liste kolonu
    LectureDetailView   detay kolonu, silme
    LectureEditor       alanlar — detay ve yeni ders sayfası aynı kodu kullanıyor
    NewLectureSheet     yeni ders
    Components/         NameSuggestField (tamamlama), Chip
  Support/
    TimeOfDay           dakika ↔ Date köprüsü
    SearchText          Türkçe duyarlı metin katlama
    ModelContext+FindOrCreate
    Color+Hex
```

## İsim eşleştirme

Aynı konunun iki yazımla birikmemesi `SearchText.fold` ile sağlanıyor: Türkçe
harfler düzleştirilip büyük/küçük harf ve aksan yok sayılıyor, sonra
`findOrCreate…` yazdığın ismi mevcut kayıtla karşılaştırıyor. Yani "BİYOFİZİK"
yazsan da var olan "Biyofizik" kaydına bağlanır.

Burada Unicode'un standart aksan katlaması yetmiyor: `ğ ş ç ö ü` kendiliğinden
düz harflere dönüyor ama `ı` (U+0131) üzerinde silinecek bir işaret olmayan ayrı
bir harf, yani asla `i` olmuyor. `SearchText` içindeki harf haritası bu boşluğu
kapatıyor.
