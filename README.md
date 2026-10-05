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

## Ekranlar

Kalıcı kenar çubuğu, ortada seçilen bölümün listesi, sağda seçilen kayıt.

| Bölüm | Liste | Detay |
| --- | --- | --- |
| Takvim | Aylık ızgara; oturum olan günler komite rengiyle noktalı | O günün oturumları, saate göre sıralı; o güne oturum ekleme |
| Konular | Tüm oturumlar, tarihe göre tersten | Alanlar canlı düzenlenir, silme onaylı |
| Dersler | Anatomi, Biyofizik… | Ad, renk, o dersin oturumları |
| Akademisyenler | Unvanlı ad, bölüm | Ad, unvan, bölüm, e-posta, verdiği oturumlar |
| Komiteler | Tarih aralığına göre sıralı | Ad, tarih aralığı, renk, oturumlar **derse göre gruplu** |
| Etiketler | Ad, oturum sayısı | Ad, renk, oturumlar, **başka etiketle birleştirme** |

Her bölüm kendi seçimini `AppNavigation` içinde tutuyor, yani
Akademisyenler'den çıkıp dönünce aynı kişide kalıyorsun. Aynı ortak nesne
sayesinde bir akademisyenin altındaki oturum satırına tıklamak seni
Konular bölümüne, o oturuma götürüyor.

## Takvim ızgarası

`MonthGrid` her ay için sabit 6 satır (42 hücre) üretiyor; ay değiştirince
ızgara satır kazanıp kaybetmediği için yükseklik oynamıyor. 6 satır her zaman
yetiyor: en geniş durum, ilk günü haftanın sonuna düşen 31 günlük bir ay ve
37 hücre istiyor. Haftanın ilk günü kullanıcının takvim ayarından geliyor
(Türkçe'de Pazartesi), sabitlenmiş değil.

Bu mantık Swift'te denenemediği için aynı hesap Python'da kurulup 2024-2030
arası 168 ay ve iki hafta başlangıcı için doğrulandı: ızgaranın doğru günle
başladığı, ayın tamamını kapsadığı ve 42 günün kesintisiz olduğu.

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
- [x] **3. Kenar çubuğu ve ilişkili ekranlar** — Ders, Akademisyen, Komite, Etiket
- [x] **4. Aylık takvim** — ızgara, gün seçimi, günden oturum ekleme
- [ ] 5. Dosya bağlama ve QuickLook
- [ ] 6. Otomatik klasör tarama ve eşleştirme
- [ ] 7. Arama ve JSON dışa aktarma

## Dosya düzeni

```
MED/
  MEDApp.swift          @main, ModelContainer kurulumu
  Models/               Lecture, Course, Instructor, Committee, Tag, LectureFile
  Views/
    ContentView         üç kolonlu kabuk, bölüm anahtarları
    SidebarView         kalıcı kenar çubuğu
    CalendarMonthView   aylık ızgara
    CalendarDayColumn   seçili günün oturumları
    LectureListView     Konular listesi
    LectureEditor       oturum alanları — detay ve yeni kayıt aynı kodu kullanıyor
    LectureDetailView   oturum detayı
    NewLectureSheet     yeni oturum
    RelatedColumns      dört varlığın liste ve detay kolonları (bağlantı katmanı)
    CourseDetailView  InstructorDetailView  CommitteeDetailView  TagDetailView
    Components/
      NameSuggestField  tamamlamalı isim alanı
      NameListColumn    dört bölümün paylaştığı liste kolonu
      LectureLinkList   "ait olduğu oturumlar" listesi, oturuma atlar
      ColorSwatchPicker  Chip  DeleteRecordButton
  Support/
    AppNavigation       bölüm ve seçim durumu
    TimeOfDay           dakika ↔ Date köprüsü
    MonthGrid           aylık ızgaranın 42 hücresi
    SearchText          Türkçe duyarlı metin katlama
    Palette             ders/komite/etiket renkleri
    ModelContext+FindOrCreate
    Color+Hex
tools/
  add_to_xcodeproj.py   proje dosyasına Swift dosyası ekler
```

## Proje dosyası

`MED.xcodeproj` elle yazıldı (klasik biçim, `objectVersion 56`). Yeni bir
Swift dosyası eklerken pbxproj'da dört yere dokunmak gerekiyor, bu yüzden iş
bir araca bağlandı:

```
python3 tools/add_to_xcodeproj.py MED/Views/Foo.swift
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
