# MED — Ders Takip Uygulaması

*[English version / İngilizce sürüm](README.en.md)*

Tıp fakültesi için ders arşivi, macOS uygulaması. Native SwiftUI, tek
kullanıcı, hesap yok, sunucu yok, abonelik yok. Lisans: [MIT](LICENSE).

## Kurulum

**Sürümden:** [releases sayfasından](../../releases) `MED.dmg` indir, aç,
**MED**'i Applications'a sürükle. Uygulama **imzasız** dağıtıldığı için ilk
açılışta macOS "geliştirici doğrulanamadı" diyecek: **Sistem Ayarları →
Gizlilik ve Güvenlik**'i aç, aşağıdaki MED satırındaki **"Yine de Aç"**
düğmesine bas. Bir kez yapılıyor.

**Kaynaktan:** macOS 14+ ve Xcode 15+ yeterli, Apple Developer hesabı
gerekmiyor.


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

## Modele alan eklerken

Var olan bir veritabanına yeni alan eklemenin bir tuzağı var ve bir kez
düşüldü:

**SwiftData yeni alanı eski satırlara doldurmuyor.** Swift'teki varsayılan
yalnızca o andan sonra oluşan kayıtlar için geçerli; eldeki satırların o
kolonu `NULL` kalıyor.

- `String`, `Int`, `Date` gibi **düz tipler sorun değil** — varsayılan,
  veritabanının kendi metadata'sına yazılabildiği için eski satırlar da
  doluyor. (`Committee.code` böyle eklendi.)
- **Codable enum'da sorun var.** Varsayılan metadata'ya yazılamıyor, kolon
  `NULL` kalıyor ve opsiyonel olmayan bir enum'u `NULL`'dan okumak
  `Could not cast value of type 'Swift.Optional<Any>'` ile çöküyor. Üstelik
  bu `ModelContainer` kurulurken değil, **ilk satır okunurken** oluyor —
  yani uygulama açılıyor, pencere hiç gelmiyor.

Kural: **sonradan eklenen enum alanı opsiyonel saklanır, opsiyonel olmayan
bir hesaplanmış özellikten okunur.** `Lecture.formatRaw` / `Lecture.format`
bunun örneği. Çağrı yerleri değişmiyor, eski kayıtlar makul bir varsayılanla
okunuyor, göç gerekmiyor.

Şemanın ilk halinde olan enum'lar (`LectureFile.kind`) bu kuralın dışında —
`NULL` satırı hiç olmadı.

## Veri modeli

Merkezde `Lecture` var — tek bir oturum. Diğer beş varlık ona bağlanıyor.

| Varlık | Ne | Not |
| --- | --- | --- |
| `Lecture` | Bir oturum | `title` o günün **konusu**, `format` teorik/pratik. Saatler `startMinutes` / `endMinutes` olarak gece yarısından itibaren dakika cinsinden; `date` yalnızca günü taşır. |
| `Course` | Tekrar eden ders — Anatomi, Biyofizik | Diskteki ders klasörünün karşılığı. Bilerek komiteye bağlı **değil**: aynı ders birden çok komitede geçiyor. |
| `Committee` | Komite I, II… | Aylık takvimdeki nokta rengi **dersten** gelir, komiteden değil — komite haftalarca sürdüğü için ayın her gününü aynı renge boyar ve hiçbir şey anlatmaz. `name` gerçek başlık ("Introduction to Medicine"), `code` kısa hali ("Komite I") — uzun ad çipe sığmıyor. Tarih aralığı oturumun komitesini belirliyor. |
| `Instructor` | Akademisyen | Akademik unvan alanının adı `titleText` — `Lecture.title` ile karışmasın. |
| `Tag` | Serbest etiket | Oturumları **enine kesen** konular: membran, sınavda çıktı. Yapısal seviye `Course`, serbest etiket `Tag`. `name` tekil (`@Attribute(.unique)`). |
| `PastExam` | Bir komitenin çıkmış sınavı | Yıl (`startYear`) ve dil (Türkçe/İngilizce). Komiteye bağlı; komite silinirse kayıtlar da silinir. |
| `LectureFile` | Diskteki bir dosyaya işaretçi | Yol `relativePath`'te; `bookmarkData` yalnızca sandbox açılırsa gerekir. Sahibi bir **oturum ya da bir çıkmış sınav**. |

`Course`, `Committee` ve `Instructor` oturumda tekil ve boş bırakılabilir.
`Tag` çoklu ve çift yönlü. `LectureFile` çoklu ve tek bir oturuma ait.

Silme kuralları:

- `Course`, `Instructor` veya `Committee` silinirse **oturumlar silinmez**, ilgili alan boşalır (`.nullify`).
- Bir oturum silinirse `LectureFile` kayıtları silinir (`.cascade`), **diskteki dosyaya dokunulmaz**.

## Ekranlar

Kalıcı kenar çubuğu, ortada seçilen bölümün listesi, sağda seçilen kayıt.

| Bölüm | Liste | Detay |
| --- | --- | --- |
| Takvim | Aylık ızgara; oturum olan günler komite rengiyle noktalı | **Hafta** (ızgara) veya **Gün** (satır satır) — araç çubuğundan seçilir |
| Konular | Tüm oturumlar, tarihe göre tersten | Alanlar canlı düzenlenir, silme onaylı |
| Dersler | Anatomi, Biyofizik… | Ad, renk, o dersin oturumları |
| Akademisyenler | Unvanlı ad, bölüm | Ad, unvan, bölüm, e-posta, verdiği oturumlar |
| Komiteler | Tarih aralığına göre sıralı | Ad, tarih aralığı, renk, **çıkmışlar**, oturumlar **derse göre gruplu** |
| Etiketler | Ad, oturum sayısı | Ad, renk, oturumlar, **başka etiketle birleştirme** |

Her bölüm kendi seçimini `AppNavigation` içinde tutuyor, yani
Akademisyenler'den çıkıp dönünce aynı kişide kalıyorsun. Aynı ortak nesne
sayesinde bir akademisyenin altındaki oturum satırına tıklamak seni
Konular bölümüne, o oturuma götürüyor.

## Oturum editöründe ne oluşturulabilir

Ders, komite ve akademisyen editörde **seçilir, oluşturulmaz.** Yıl içinde
sekiz on ders ve yedi komite oluyor; bunlar kendi bölümlerinde bir kez
kurulur. Yüzlerce kez kullanılan bir formda duran "ara veya ekle" alanının
bedeli her seferinde ödeniyor, karşılığı ise yılda birkaç kez.

Tek istisna akademisyen: yıl içinde yeni bir hoca çıkıyor, o yüzden seçim
listesinin yanında bir `+` düğmesi var. Etiketler de akış içinde
oluşturuluyor, onların alanı duruyor.

## Sıralama ve liste içi arama

`LectureSort` dört seçenek sunuyor: yeniden eskiye, eskiden yeniye,
konu A→Z, konu Z→A. Seçim `@AppStorage` ile hatırlanıyor — bir kez
seçtiğin sırayı her derste yeniden seçmek istemezsin.

- **Yeniden eskiye** baştan sona ters kronolojik: en yeni gün üstte, **o gün
  içinde en geç ders üstte.** İki yönü karıştırmak (yeni gün üstte ama erken
  ders üstte) hata gibi okunuyor, çünkü bir günün en yeni dersi son dersidir.
- **Alfabetik sıralama** `localizedStandardCompare` kullanıyor, katlama
  değil: Türkçe'de ı harfi i'den önce gelir ve bunu yerel ayar bilir,
  düzleştirilmiş bir karşılaştırma bilmez.
- **Takvimin gün kolonu** sıralama seçimini yok sayıp her zaman eskiden
  yeniye diziliyor: orada liste tek bir güne ait, uyulacak bir tarih ekseni
  yok, program gibi okunması gerekiyor.

Dört sıralamanın tanımı `LectureSort.precedes` içinde, tek yerde:
ikisi `displayTitle`'a (hesaplanan başlık) göre sıraladığı için hiçbir
`SortDescriptor` bunları ifade edemiyor, ve tek tanım Konular listesiyle
ilişkili ekranların "en yeni" konusunda anlaşmazlığa düşmesini engelliyor.

İlişkili ekranlardaki listede **arama çubuğu** var (konu, ders, akademisyen,
komite, etiket, not, dosya adı). Beşten az satırda görünmüyor — bir tutam
satırı aramak yardım değil gürültü.

## Yeri değişmiş dosyalar

Konular'ın araç çubuğundaki **Dosya işlemleri** menüsünde, klasör taramasının
yanında: ikisi de seyrek, ikisi de aynı soruyu soruyor — diskteki dosyalarla
kayıtlar hâlâ örtüşüyor mu?

Uygulama dosyaların yerini saklıyor, kopyasını tutmuyor. Finder'da taşıdığın
bir dosyanın kaydı boşa düşüyor ve bunu ancak o derse girince görüyorsun —
`FileHealth` bütün arşiv için tek seferde cevaplıyor.

Her satırda iki çıkış var: **"Yerini göster…"** kaydı dosyanın şimdiki yerine
yöneltiyor, **"Kaydı kaldır"** dosyanın nerede olduğunu unutuyor ve dosyaya
dokunmuyor.

Kök klasör seçilmemişken göreli yollar **bozuk sayılmıyor.** Çözülememek
bozuk olmakla aynı şey değil; saymak, kök klasörü kaldırdığın anda arşivdeki
her dosyanın kaybolduğunu söylerdi.

## Konular ekranı: arama ve filtre

Arşivin tamamını gören tek ekran Konular, o yüzden arama ve filtre ayrı bir
"Arama" bölümü olarak değil burada duruyor. İkinci bir arama yeri, bir isabetin
ne olduğu konusunda bununla çelişebilecek ikinci bir yer demek olurdu ve
karşılığı yok: kenar çubuğunun kendi bölümleri "hangi derslerim var"ı
zaten cevaplıyor.

- **Arama** `.searchable` ile araç çubuğunda, `LectureSearch` ile aynı
  eşleştirme (konu, ders, akademisyen, komite, etiket, not, dosya adı).
- **Filtre** `LectureFilter`: ders, akademisyen, komite, tür ve "dosyası
  olmayanlar". Alanlar birbiriyle birleşiyor, her alanda tek seçim var —
  "Anatomi ya da Biyokimya" sorduğun soru değil.
- **Filtre hatırlanmıyor**, sıralama hatırlanıyor. Sıralama bir kez verdiğin
  tercih; filtre şu an sorduğun soru. Uygulamayı açtığında arşivin yarısının
  eksik olduğu bir listeyle karşılaşmak veri kaybı gibi okunur.
- **Açık filtreler listenin üstünde çip olarak yazılı.** Araç çubuğundaki dolu
  ikon bir şeyin filtrelendiğini söyleyebilir, *neyin* filtrelendiğini
  söyleyemez; bir filtrenin asla sessizce yapmaması gereken tek şey o. Her çip
  kendi koşulunu kaldırıyor.
- **Parça numaraları ve dosya boşlukları arşivin tamamından okunuyor**,
  görünen listeden değil: filtre kardeşini saklarken 2 parçalı konunun birinci
  parçası "(1/2)" kalıyor, ve dosyayı taşıyan parça filtrelendiği için bir
  konu "slaytı eksik" olmuyor.
- **Silme satırın gösterdiği kaydı siliyor.** Filtrelenmemiş sorguya indeksle
  erişmek, bir filtre/arama ya da varsayılan dışı bir sıralama açık olduğu
  anda silinen satırdan başka bir oturumu silerdi.

Satırın üst satırında ders adı ve **kaç ders sürdüğü** yazıyor, konu adının
yanında değil: oraya konmuş bir çip konunun sarılacağı genişliği yiyor, uzun
bir ad aynı şeyi söylemek için fazladan bir satır harcıyordu. Yukarıda hiçbir
şeye mal olmuyor — ders adı iki kelime ve satır zaten boş.

Satırlarda **ataç ikonu** dosyası olanları gösteriyor. Asıl faydası tersi:
hangi konuların slaytı eksik, listeye bakınca görünüyor.

## Geri alma (⌘Z)

`ContentView` pencerenin `UndoManager`'ını `modelContext`'e veriyor. Kendi
`UndoManager`'ını yaratmak işe yaramaz: her değişikliği düzgünce kaydeder ama
⌘Z hiçbir şey yapmaz, çünkü Düzen menüsü onu tanımaz — menü, sorumluluk
zincirinin kendisine verdiği yöneticiyi kullanır, bu da metin alanı dışındaki
her şey için pencerenin yöneticisidir.

`MEDApp` içinde değil `ContentView` içinde kuruluyor: `modelContext` ancak
`.modelContainer(_:)`'ın altında var, ve o değiştirici bu görünüme uygulanıyor.

## İki dil

Arayüz Türkçe ve İngilizce. Ayarlar'dan (⌘,) seçiliyor ve **hemen** değişiyor.
macOS'un alışıldık yolu — `AppleLanguages`'i defaults'a yazmak — yeniden
başlatma istiyor, ki menüden dil seçmiş birinden istenecek tuhaf bir şey.

### Dizgeler kullanıldıkları yerde

`L.pick("Konular", "Topics")`. Birkaç yerde geçen sözcükler `L` içinde
adlandırılmış (`L.cancel`, `L.sessionCount(_:)`), gerisi yerinde duruyor.
Alışıldık anahtar-tablo düzeninin tersi, üç gerekçeyle:

- **Çevirisiz kalmak imkânsız.** İki dil aynı çağrının argümanı, yani eksik
  olan derleme hatası veriyor — çalışma zamanında kendi adına düşen bir
  anahtar değil. Derleyicisiz çalışılan bir projede bu, tablodan daha
  değerli.
- **İki sürüm yan yana ve bağlamın içinde.** Tablo, bir dili bir dosyada
  diğerini başka dosyada okutur; `scanWeakFooter` gibi bir ad da cümleyi
  cümlenin anlattığı kadar anlatmaz.
- Anahtar yanlış yazılamıyor, öksüz kalamıyor, Türkçede denk düşen iki ayrı
  cümle için sessizce kullanılamıyor.

### Dil neden ortak bir nesnede

`AppLanguage.shared`, `@Observable`. Dizgeler yalnızca görünümlerde değil: bir
oturumun `displayTitle`'ı, `LessonSlot`'un "3. ders"i, `LectureSort`'un adları
da dile ihtiyaç duyuyor ve hiçbiri environment'a uzanamıyor. Görünümler için
gözlem yine çalışıyor — dili `body` içinde okumak bağımlılığı kaydediyor, o
yüzden dil değişince sözcük gösteren her şey yeniden çiziliyor.

Tarihler ve ay adları da seçilen dile uyuyor: `ContentView` pencereye
`\.locale` veriyor, görünüm dışında üretilen tarihlere (`WeekGrid.title`,
`Committee.dateRangeText`, ayın adı, gün kısaltmaları) dil `L.format` ile
ayrıca söyleniyor — `Date.formatted` süreç yerelini okur, pencerenin değil.

### İki dilde ölçü

İngilizce dizgeler Türkçe karşılıklarından uzun olabiliyor ve bir dile göre
ölçülmüş sabit genişlik ikinci dilde taşıyor. İki önlem:

- **Kendi içeriğine göre ölçülenler** `.fixedSize()` kullanıyor. Süre seçicisi
  bunun yüzünden bozulmuştu: `.frame(width: 200)` "1 ders"e göre ölçülmüştü,
  "3 lessons" sığmıyordu, ve sığmayan bir segmented control küçülmek yerine
  yanındakinin üstüne çiziyor.
- **Hizalanmak için sabit kalmak zorunda olanlar** (hafta ızgarasının saat
  kolonu, gün görünümünün etiket kolonu, liste satırlarının öndeki kolonu) iki
  dilin uzununa göre ölçülü, üstüne `lineLimit(1)` ve `minimumScaleFactor`:
  taşmak yerine bir tık küçülüyorlar.

Süre seçicisinin özet satırı da yanından altına indi. Orada hem seçilenin hem
imlecin altındaki dersin saatleri yazıyor, yani genişliğe ihtiyacı var ve alt
satırda çarpışacağı bir şey yok.

### Çevrilmeyenler

- **Senin yazdığın her şey.** Ders adları, konular, akademisyen adları,
  notlar, etiketler. Veri çeviri konusu değil.
- **macOS'un kendi menüleri** — Dosya, Düzen, Pencere, Yardım — Mac'in
  dilinde kalıyor; onları değiştirmenin yolu yeniden başlatma gerektiren
  `AppleLanguages`'ten geçiyor. Uygulamanın kendi menü maddesi
  ("JSON olarak dışa aktar…") dili takip ediyor.
- **Arama katlaması** (`SearchText`) her iki dilde de Türkçe harfleri
  düzleştiriyor. Veri Türkçe; arayüzün dili aramanın nasıl eşleşeceğini
  değiştirmemeli.

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

## Haftalık ızgara

Günler yanda, dokuz ders saati altta; her oturum dersinin rengiyle dolu bir
kutu. Boş hücre `+` ile o güne ve o saate oturum açıyor — bir haftanın
programını girmenin en hızlı yolu bu.

Hem hafta ızgarası hem gün görünümü aynı `DayTimetable` üzerinden
diziliyor — bir günü "N derslik blok" ve "boş hücre" dizisine çeviren tek
mantık. Gün görünümünde bir blok `2.–3. ders · 09:40–11:10` etiketli tek
satır oluyor; bilgiler bir kez yazılıyor, ikinci satırda "devam ediyor"
demek yerine.

Izgara **satır satır değil, gün gün** diziliyor. Sebebi çift ders: iki
ders saatlik bir oturum, iki ayrı hücre değil **tek uzun bir kutu** olmalı,
yoksa farklı dersler gibi görünüyor. `DayTimetable.segments` bir günü
"N derslik blok" ve "boş hücre" dizisine çeviriyor; blok yüksekliği
`N × satır + (N-1) × boşluk` oluyor. Kritik değişmez şu: span'lerin toplamı
her durumda dokuz, yani her sütun aynı yükseklikte kalıyor ve satırlar
soldaki saat kolonuyla hizalı duruyor. On iki yerleşim üzerinde doğrulandı —
gün sonunda kırpılan blok, aynı saati isteyen iki oturum, ve içinde başka
bir dersin başladığı çift ders dahil.

**Aşağı doldurma:** bir bloğun üzerine gelince sağ alt köşesinde çıkan ok,
aynı oturumu bir sonraki ders saatine **ayrı bir kayıt olarak** kopyalıyor.

Ok imleçle görünüyor, çünkü bu bir giriş kısayolu: bir hafta yazıldıktan
sonra her blokta duran bir ok gürültü. Günü bazında gizlemek — mesela bir
sonraki günde kayıt varsa saklamak — işin bitip bitmediği hakkında tahmin
yürütür ve üç durumda yanılır: günleri sırayla girmezsen, eski bir güne
dönüp düzeltirsen, ve Cuma'da (bir sonraki günü hafta sonu, hep boş kalıyor).
Bloğa bakmak ise tahmin değil. Okulda tek bir
konu iki ders saati boyunca işlenebiliyor ama bunlar ayrı dersler olarak
sayılıyor; o yüzden uzatmıyor, çoğaltıyor. Ders, akademisyen, komite, tür ve
etiketler kopyalanıyor; notlar ve dosyalar kopyalanmıyor — onlar oturuma ait,
konuya değil. Ok yalnızca gereken saatlerin tamamı boşsa görünüyor.

Yerleşim kararı: haftalık ızgara **geniş olan sağ kolonda**, aylık ızgara
solda kalıyor. Beş sütun ders bloğu liste genişliğindeki bir kolona sığmıyor.
Ay ızgarasından bir güne tıklamak haftayı oraya taşıyor; hafta oklarıyla
gezinmek de ay ızgarasını takip ettiriyor.

Hafta içi beş gün her zaman görünüyor. Hafta sonu sütunları yalnızca o güne
bir şey kayıtlıysa ekleniyor — tek seferlik bir cumartesi dersi gizlenmiyor.
Programa oturmayan kayıtlar (seminer, sınav) ızgaranın altında ayrı bir
satırda.

Hafta sınırı hesabı Python'da doğrulandı: 2024-2030 arası 252 tarih, hem
Pazartesi hem Pazar başlangıçlı takvimle.

## Bir konu, birkaç ders

Okulda tek bir konu iki ders saati boyunca işlenebiliyor ama bunlar ayrı
dersler olarak sayılıyor — aralarında 10 dakika teneffüs var. Bu, bir
oturumun iki ders saati **sürmesinden** farklı bir şey ve ikisi farklı
görünmeli:

| | Kayıt | Hafta ızgarası | İlişkili listeler |
| --- | --- | --- | --- |
| **Uzun tek oturum** (süre: 2 ders) | 1 kayıt | Tek uzun kutu | Tek satır |
| **Aynı konu, iki ders** (aşağı doldurma) | 2 kayıt | İki kutu: `… (1)` ve `… (2)` | Tek satır, "2 ders" etiketiyle |

Gruplama **türetiliyor, saklanmıyor.** İki oturum *aynı gün + aynı ders +
aynı konu + aynı tür* ise aynı konunun parçalarıdır — "aradan sonra devam
eden aynı ders" tam olarak bu demek, ve aşağı doldurma da tam bu şekli
üretiyor. Yeni alan, göç, bozulacak bağ yok; elle aynı konuyu iki kez yazsan
da gruplanıyor. Tek bedeli: bir parçanın adını değiştirmek onu ayırıyor —
ki zaten doğru cevap bu.

Konusu boş oturumlar hiç gruplanmıyor: aynı derste aynı gün iki başlıksız
oturum, tek konu olduklarına dair kanıt değil.

Gruplama **ilişkili ekranlarda** yapılıyor (Ders, Akademisyen, Komite,
Etiket) — oralardaki liste bir gezinme aracı. **Konular** listesinde
yapılmıyor, çünkü orada liste seçimi detay editörünü sürüyor; grupladığım
anda ikinci parça düzenlenemez hale gelirdi. Takvimde de her parça kendi
kutusunda ve tıklanabilir.

**Dosyalar konunun tamamına ait.** İki ders aynı slayttan işleniyor —
aradaki teneffüs ikinci bir slayt dağıtmıyor. Bir parçaya bağlanan dosya
diğerinden de görünüyor; eklediğinde baktığın parçaya bağlanıyor,
kaldırdığında hangisinde duruyorsa oradan kalkıyor.

On altı vaka Python'da doğrulandı: aynı gün sıralaması, iki parça, üç parça,
aralıklı parçalar, uzun tek oturum, ve ayrışması gereken altı durum
(farklı konu/ders/gün/tür, iki başlıksız, büyük-küçük harf).

## Teorik, pratik, sınav

`Lecture.format` üç değerli: teorik, pratik, sınav. Editörde üçlü seçim,
varsayılan teorik — eldeki kayıtlar da teorik olarak geliyor.

**Sınav neden etiket değil de `format`?** Çünkü etiketle aynı türden bir şey
değil: her oturumda bir tek cevabı var, her zaman var, ve listeyi ona göre
filtrelediğin şey o. Etiket olsaydı opsiyonel olurdu, yanlış yazılabilirdi ve
tür filtresinde görünmezdi.

Listelerde ve ızgarada **yalnızca pratik ve sınav** işaretleniyor. Teorik
oturumlar ezici çoğunluk olduğu için onları da etiketlemek neredeyse her
satıra bir işaret koyar ve hiçbir şey anlatmaz.

İki rozet de **dolu zemin, beyaz yazı** — satırın renginin soluk bir tonu
değil. Bir ayı gözle tararken kaçırmayı göze alamayacağın iki oturum bunlar,
ve %22 saydamlıktaki bir harfi atlamak satırın geri kalanını atlamak kadar
kolay. İkisi ayrı renk (**pratik kırmızı, sınav mor**), çünkü aynı kırmızıdaki
iki dolu rozet bir bakışta aynı şey gibi okunur — ki rozetin tek işi o.

Rozet de ders adının yanında, konu adının yanında değil: aynı gerekçe, konunun
sarılacağı genişliği yemesin.

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

## Çıkmış sınavlar

Komite detayında **Çıkmışlar** bölümü. Her kayıt için iki tanım var: hangi
akademik yıl ve hangi dil (Türkçe / İngilizce). Satırı açınca dosyaları,
yıl ve dil seçicileri ve silme düğmesi çıkıyor — ayrı bir ekrana gitmeden.

Yıl `startYear` olarak **tek bir sayı** tutuluyor; 2022 demek 2022-2023
demek. Elle yazılan "2022-2023" metni "2022-23", "2022/2023" ve yazım
hatalarını davet ediyor, hiçbiri de sıralanmıyor. Akademik yıl sonbaharda
başladığı için Ocak 2026 tarihli bir gün 2025-2026'ya düşüyor.

Seçenekler **2018-2019'da duruyor** (`AcademicYear.earliestStartYear`); daha
eski çıkmışlar ortalıkta yok ve dolu bir liste sadece kaydırma demek. Kayıtlı
bir değer bu aralığın dışındaysa listede korunuyor, yani eski bir kayıt kendi
yılını kaybetmiyor.

**Segment seçici kullanılmıyor** burada: gruplu bir `Form` içindeki
`DisclosureGroup`'ta satırdan yüksek olup üstteki satırın altında kalıyor.
Dil de yıl gibi açılır liste.

Dosyalar ayrı bir varlık değil, aynı `LectureFile`: bir dosya kaydının
sahibi ya bir oturum ya bir çıkmış sınav. Böylece ikisi aynı yol çözümünü,
aynı önizlemeyi ve aynı "hiçbir şeyi kopyalamaz" güvencesini paylaşıyor;
neredeyse birebir ikinci bir varlık yazmak gerekmiyor.

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

## Klasör tarama

Konular araç çubuğundaki **Klasörü tara** (⌘⇧T) bir klasörü gezip her dosyanın
hangi oturuma ait olduğunu öneriyor.

**Asla kendiliğinden çalışmıyor.** Açılışta tarayan ya da klasörü izleyen bir
sürüm, sen bakmıyorken dosya bağlardı — ve slaytları elle bağlamaktan daha kötü
tek şey, onları yanlış derse bağlanmış bulup ne zaman olduğunu bilmemek. O
yüzden: bir buton, bir öneri listesi, ve işaretlenmeyen hiçbir şeyin
uygulanmaması.

Hiçbir dosya kopyalanmıyor, taşınmıyor, yeniden adlandırılmıyor. Eşleşme tek
bir `LectureFile` yazıyor, dosyanın hâlihazırda bulunduğu yeri gösteren.

### Nasıl eşleştiriyor

1. **Tarih — sert filtre, ipucu değil.** Dosya hakkında her şey yanlış
   olabilir (klasör, konu, yazım) ama başka bir gün işlenen ders bu dosyanın
   dersi değildir. Okuduğu biçimler: `2025-10-03`, `2025.10.03`, `2025_10_3`,
   `20251003`, `03-10-2025`, `03.10.2025`. Ayırıcılar `-`, `_`, `.` — **boşluk
   değil**: boşluğa izin vermek "Ders 1 2 2025.pdf"i tarihe çevirir. Belirsiz
   `03-10-2025` Türkçe teamüle göre 3 Ekim okunuyor. Takvimler esnek olduğu
   için (31 Şubat'ı Mart'a yuvarlarlar) tarih geri okunup karşılaştırılıyor.
2. **Klasör adı → ders.** İki yönlü içerme, en az üç harften itibaren: "Komite
   1 - Anatomi" de "Anatomi (teorik)" de Anatomi'yi buluyor. Klasör tanıdığın
   bir dersi adlandırıyor ama o gün o dersten ders yoksa **kanıt kendisiyle
   çelişiyor** — bu durumda sonuç en iyi "zayıf" olabiliyor.
3. **Konu benzerliği.** Kelime kelime, ve biri diğerinin öneki ise (kısa olan
   ≥ 4 harf) aynı kelime sayılıyor. Türkçe eklerini yapıştırdığı için
   "Enzimler" ile "Enzim kinetiği" tek ortak kelime taşımadan aynı şeyden
   bahsediyor; bütün dizge üzerinden bir düzenleme uzaklığı da, küme kesişimi
   de bunu kaçırır. Tam eşitlik 1, biri diğerinin alt dizgesi 0.85.

Puanlama **kayıt başına değil konu başına**: bir konunun parçaları dosyalarını
paylaştığı için verilecek tek bir karar var ve onu ilk parça taşıyor.

### Üç grup

| Grup | Ne demek | Varsayılan |
|---|---|---|
| **Kesin** | Tarih, klasör ve konu birbirini doğruluyor (≥ 0.6) ve ikinciyle arasında en az 0.15 fark var | **işaretli** |
| **Zayıf** | Gün doğru görünüyor ama konu kesin değil. Önerilen oturum menüden değiştirilebiliyor | işaretsiz |
| **Eşleşmedi** | O güne ait oturum yok. İşaretlenirse **dosya adından yeni oturum** oluşturuluyor | işaretsiz |

Kesinler işaretli başlıyor, gerisi başlamıyor — grupların arasındaki fark tam
olarak bu: biri bir bakış, diğerleri bir karar, ve bir tahmini varsayılan
olarak "evet" yapmak yanlış dosyanın yanlış derse gitme yoludur.

Adında hiç tarih olmayan dosya "eşleşmedi" içinde ama **işaretlenemiyor**:
oluşturulacak oturumun gününü söyleyen bir şey yok. Oluşturulan oturumun
**saati boş** kalıyor — ders programı dosya adında yazmıyor ve uydurulmuş bir
saat boş olandan kötüdür.

Uygulanan satırlar listeden düşüyor, klasör yeniden gezilmiyor: yeni tarama
`fileRecords` sorgusunu okur ve bir an önce eklenen kayıtlar o sorgunun
sonucunda henüz yok — bağlanan her dosya tekrar bulgu olarak geri gelirdi.

## Dışa aktarma ve yedek

**Dosya → JSON olarak dışa aktar…** (⌘⇧E) arşivin tamamını tek bir okunabilir
dosyaya yazıyor: dersler, akademisyenler, komiteler (çıkmışlarıyla),
etiketler, oturumlar (dosya bağlarıyla).

Her kayıt kısa bir kimlik taşıyor (`c1`, `i2`, `k1`, `t3`) ve oturumlar bu
kimlikleri gösteriyor. `PersistentIdentifier` daha az iş olurdu ve uygulamanın
dışında hiçbir işe yaramazdı: opak, ve okuyamadığın bir yedek kontrol
edemediğin bir yedektir. Bedava gelen türetilmiş alanlar da yazılıyor
(komitenin etiketi, dersin saat aralığı) — dosyanın amacı onu yazan uygulama
olmadan da anlaşılır olmak.

Anahtarlar sıralı, tarihler ISO: aynı arşivin iki aktarımı aynı baytlar
oluyor, böylece bir diff neyin değiştiğini gösteriyor, sözlüğün o gün hangi
sırayla dizildiğini değil.

**İçe aktarma yok, bilerek.** Bir dosyayı geri okumak, hâlihazırda var olan
her kayıt için ne yapılacağına karar vermek demek — birleştir, değiştir,
çoğalt — ve bunu sessizce yanlış yapmak bir arşivi ikiye katlar. Gerçek geri
yükleme yolu veritabanı dosyasının kendisi; Ayarlar (⌘,) onu gösteriyor ve
Finder'da açıyor. Kopyalanacak şey o.

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
- [x] **6. Klasör tarama ve eşleştirme** — elle tetiklenen tarama, üç güvenlik seviyesi, onay kutuları
- [x] **7. Arama ve JSON dışa aktarma** — arama/filtre Konular ekranında, dışa aktarma Dosya menüsünde

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
    CalendarWeekView    haftalık ders programı ızgarası
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
      FormatBadge       pratik işareti
      NameListColumn    dört bölümün paylaştığı liste kolonu
      LectureLinkList   "ait olduğu oturumlar" listesi, oturuma atlar
      ColorSwatchPicker  Chip  DeleteRecordButton
  Support/
    AppNavigation       bölüm ve seçim durumu
    TimeOfDay           dakika ↔ Date köprüsü
    MonthGrid           aylık ızgaranın 42 hücresi
    LessonSlot          okulun dokuz ders saati
    WeekGrid            bir haftanın günleri
    LibraryRoot         PDF kök klasörü (UserDefaults)
    FileNaming          dosya adından tür tahmini
    SearchText          Türkçe duyarlı metin katlama
    LectureGrouping     bir konunun parçaları + sıralama kuralı
    Palette             ders/komite/etiket renkleri
    ModelContext+FindOrCreate
    Color+Hex
tools/
  add_to_xcodeproj.py   proje dosyasına Swift dosyası ekler
```

## Çip satırları

Ders, komite ve etiket çipleri `FlowLayout` ile diziliyor: her çip kendi
metni kadar yer alıyor, sığmayınca alta iniyor.

Eşit sütunlu `LazyVGrid` bunu yapamıyor — sütunlar aynı genişlikte olduğu
için "Tıbbi Biyoloji ve Genetik" kesiliyor, "Anatomi" ise sütununun yarısını
boş bırakıyordu.

Sıra verildiği gibi, yani alfabetik, bırakılıyor. Satır sayısını daha da
azaltmak için çipleri yeniden sıralamak mümkün ama o zaman ders eklendikçe
veya adı değiştikçe çipler yer değiştirir; aradığını bulmak bir satır
yükseklikten değerli.

Paketleme Python'da doğrulandı: taşma yok, çip kaybı yok, satırdan geniş tek
bir ad satıra kırpılıyor, yer varsa hepsi tek satırda.

## Form içindeki metin alanları

macOS'ta gruplu bir `Form` içindeki `TextField` iki şeyi birden ters
yapıyor, ikisinin de sebebi aynı: form etiketi başa, kontrolü sona koyuyor
ve kontrolün içeriğini de sona hizalıyor. Sonuç: düzenlenebilir alan satırın
sağ ucunda kalıyor (yazmak için sağ tarafa tıklamak gerekiyor) ve yazı sabit
bir imleçten sola doğru büyüyor.

Bu yüzden her metin alanı `.formTextField()` taşıyor. Etiketi yalnızca yer
tutucu olsun diye verilen alanlar (arama çubuğu, tamamlamalı isim alanı)
`.borderlessFormTextField()` kullanıyor: o da etiketi satır düzeninden
çıkarıyor, böylece alan tam genişlikte ve her yerinden tıklanabilir oluyor.

## Derleme öncesi tarama

Bu projede Swift derleyicisi yok — kod kör yazılıp Xcode'da derleniyor. Bu
yüzden yaşanan her derleme hatası için bir kontrol eklendi:

```
python3 tools/check_swift.py
```

| Kontrol | Yakaladığı gerçek hata |
| --- | --- |
| Tanımsız üye çağrısı | Dosya yeniden yazılırken düşen `headerBackground` |
| Eksik argüman etiketi | İmzası değişen `add(in:)` → `add(on:in:)` çağrısı |
| Demet üzerinde key path | `ForEach(..., id: \.offset)` — Swift izin vermiyor, iki kez yazıldı |
| Zincirli baştan-nokta | `.quaternary.opacity(...)` — jenerik `ShapeStyle` konumunda tip çıkarımı kırılgan |
| `ForEach` closure'ında yerel let | — |
| Sunum değiştiricisine sentetik `Binding` | `fileImporter`'ın kapanışı hedefi silince çıkmış sınava eklenen dosya hiçbir yere gitmiyordu |

Her kontrol, yakalaması gereken hata geri konularak sınandı.

Son kural bir kalıbı yasaklıyor: `isPresented:` gibi bir sunum bağlamasına
`Binding(get:set:)` vermek. Kapanış o setter'ı çalıştırıyor, setter da
tamamlanma bloğunun okuyacağı durumu siliyor. Sunum durumu ile hedef durumu
ayrı tutulmalı.

### Yakalanan hata sınıfları

Her kural gerçek bir hatadan doğdu ve hatayı yeniden sokarak kanıtlandı:

1. Tanımsız üye çağrısı (dosya yeniden yazılırken düşen yardımcı)
2. Eksik argüman etiketi — trailing closure'ı tanıyor
3. Demet üzerinde key path (`ForEach(x.enumerated(), id: \.offset)`)
4. Jenerik ShapeStyle konumunda zincirli baştan-nokta
5. ForEach closure'ında yerel `let`
6. Sunum değiştiricisine sentetik `Binding` — setter, tamamlanma bloğunun
   okuduğu durumu siler
7. `DateFormatter`'ın sembol dizileri (`shortWeekdaySymbols` ve kardeşleri)
   `[String]?` geliyor, `[String]!` değil: doğrudan indekslemek derlenmiyor

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
