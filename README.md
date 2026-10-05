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

Uygulama App Store'a gönderilmeyeceği için sandbox açılmadı. Tek sebebi
sadelik: sandbox altında iCloud klasörüne erişmek güvenlik kapsamlı yer imi
(security-scoped bookmark) makinesi gerektiriyor — bayatlayan yer imleri, her
açılışta izni geri alma, `startAccessingSecurityScopedResource`. Kapalıyken
düz dosya yolu yetiyor ve o katman tümden yok.

`LectureFile.bookmarkData` alanı yerinde duruyor ama kullanılmıyor; sandbox'ı
sonradan açmak isterseniz yeri hazır.

## Veri modeli

Merkezde `Lecture` var — tek bir oturum. Diğer beş varlık ona bağlanıyor.

| Varlık | Ne | Not |
| --- | --- | --- |
| `Lecture` | Bir oturum | `title` o günün **konusu**. Saatler `startMinutes` / `endMinutes` olarak gece yarısından itibaren dakika cinsinden; `date` yalnızca günü taşır. |
| `Course` | Tekrar eden ders — Anatomi, Biyofizik | Diskteki ders klasörünün karşılığı. Bilerek komiteye bağlı **değil**: aynı ders birden çok komitede geçiyor. |
| `Committee` | Komite I, II… | `name` gerçek başlık ("Introduction to Medicine"), `code` kısa hali ("Komite I") — uzun ad çipe sığmıyor. Tarih aralığı oturumun komitesini belirliyor. |
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
| Takvim | Aylık ızgara; oturum olan günler komite rengiyle noktalı | Hafta içi: dokuz ders saati, boş olanlar doldurulmaya hazır. Hafta sonu: düz liste |
| Konular | Tüm oturumlar, tarihe göre tersten | Alanlar canlı düzenlenir, silme onaylı |
| Dersler | Anatomi, Biyofizik… | Ad, renk, o dersin oturumları |
| Akademisyenler | Unvanlı ad, bölüm | Ad, unvan, bölüm, e-posta, verdiği oturumlar |
| Komiteler | Tarih aralığına göre sıralı | Ad, tarih aralığı, renk, oturumlar **derse göre gruplu** |
| Etiketler | Ad, oturum sayısı | Ad, renk, oturumlar, **başka etiketle birleştirme** |

Her bölüm kendi seçimini `AppNavigation` içinde tutuyor, yani
Akademisyenler'den çıkıp dönünce aynı kişide kalıyorsun. Aynı ortak nesne
sayesinde bir akademisyenin altındaki oturum satırına tıklamak seni
Konular bölümüne, o oturuma götürüyor.

## Elle doldurulmayan alanlar

Yüzlerce oturum girilecek, aynı cevabı tekrar tekrar yazmamak için üç yerde
veri kendini dolduruyor. Üçünün de kuralı aynı: **yalnızca alan boşken yazar,**
seçtiğin hiçbir şeyi ezmez.

| Alan | Neden çıkarılabiliyor | Ne zaman |
| --- | --- | --- |
| **Komite** | Komitenin tarih aralığı var, oturumun tarihi var | Yeni oturumda ve tarih değişince |
| **Ders** | Akademisyen → ders çoğa-bir | Akademisyen seçilince, o hocanın derslerinin en az 2/3'ü tek derse düşüyorsa |
| **Tür** (slayt/not) | Dosya adı | Dosya bağlanınca |

Tersi yapılmıyor: ders → akademisyen bire-çok (bir derse birden çok hoca
giriyor), o yüzden tahmin edilmiyor.

Komite tarihle çelişirse **sessizce değiştirilmiyor** — editörde "Bu tarih
Komite II aralığında · Uygula" satırı çıkıyor. Çünkü istisna bilerek yapılmış
olabilir: telafi dersi, komite dışı seminer. İki komitenin aralığı aynı günü
kapsıyorsa tahmin yok, alan boş kalıyor.

Komiteyi sonradan açtığında geriye dönük atama var: komite detayında
"Bu aralıkta komitesi boş 14 oturum var · ata".

Ders seçimi arama alanı değil, **bütün dersler düğme** — yıl içinde sekiz on
ders oluyor, görebildiğin bir şeyi aramak gereksiz iş.

## Ders saatleri

Okulun hafta içi programı sabit: dokuz ders, her biri 40 dakika, aralar 10
dakika, 5. ile 6. ders arasında 60 dakika öğle arası.

| | | | | | | | | |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
| 08:50 | 09:40 | 10:30 | 11:20 | 12:10 | 13:50 | 14:40 | 15:30 | 16:20 |

Bu tablo `LessonSlot` içinde **kod**, veri değil. Oturumda saklanan şey yine
gerçek saatler (`startMinutes` / `endMinutes`); ders numarası bunlardan
*türetiliyor*. Sonucu şu:

- Program değişirse `LessonSlot.all` içinde bir satır düzeltilir, göç gerekmez.
- Eski kayıtlar gerçek saatlerini korur; programa oturmayanlar "özel saat"
  olarak görünür ve gün görünümünde "Program dışı" başlığına düşer.
- Senkronu bozulacak bir kip yok: slot düğmeleri yalnızca saatleri yazıyor,
  seçili görünen şey de aynı saatlerden geri okunuyor.

Çift ders (08:50–10:20 gibi) destekli: süre seçicisi 1-3 ders arası uzatıyor,
gün görünümünde ilk dersin satırında "2 ders" etiketiyle çıkıyor, kapsadığı
sonraki ders satırı "devam ediyor" diyor.

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

## Dosyalar

Kök klasör bir kez Ayarlar'dan (⌘,) seçiliyor ve bir yol olarak saklanıyor.
Bir dosya bağlanırken yolu **kökün altındaysa köke göreli**, değilse mutlak
olarak kaydediliyor. Göreli yol, kök klasörü taşısan ya da yeniden
adlandırsan da bağların kopmaması demek.

Oturum detayında dosyalar Slaytlar / Notlarım / Diğer başlıkları altında
gruplu. Satıra tıklamak QuickLook ile uygulama içinde önizliyor, klasör
simgesi Finder'da gösteriyor, ok simgesi varsayılan uygulamada açıyor.
Diskte bulunamayan dosya sessizce kalmıyor, uyarı simgesiyle söylüyor.

Tür (slayt / not) dosya adından tahmin ediliyor. Kural **tam kelime**
eşleştiriyor, alt dizge değil: "Notochord gelişimi" içinde "not" geçiyor ama
not değil. On üç gerçekçi dosya adı üzerinde alt dizge kuralı beşini yanlış
sınıflandırıyordu.

Hiçbir işlem dosyayı kopyalamıyor, taşımıyor, yeniden adlandırmıyor,
silmiyor. Listeden kaldırmak yalnızca yerini unutuyor.

## Önerilen klasör düzeni

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
- [x] **5. Dosya bağlama ve QuickLook** — elle ekleme, önizleme, Finder'da gösterme
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
    LectureFilesSection oturumun dosyaları, QuickLook
    SettingsView        kök klasör ayarı (⌘,)
    RelatedColumns      dört varlığın liste ve detay kolonları (bağlantı katmanı)
    CourseDetailView  InstructorDetailView  CommitteeDetailView  TagDetailView
    Components/
      NameSuggestField  tamamlamalı isim alanı
      SlotPicker        ders saati seçici
      NameListColumn    dört bölümün paylaştığı liste kolonu
      LectureLinkList   "ait olduğu oturumlar" listesi, oturuma atlar
      ColorSwatchPicker  Chip  DeleteRecordButton
  Support/
    AppNavigation       bölüm ve seçim durumu
    TimeOfDay           dakika ↔ Date köprüsü
    MonthGrid           aylık ızgaranın 42 hücresi
    LessonSlot          okulun dokuz ders saati
    LibraryRoot         PDF kök klasörü (UserDefaults)
    FileNaming          dosya adından tür tahmini
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
