# MED — Ders Takip Uygulaması: Teknik Tarif

Oct 5, 2026

## Amaç ve kapsam

Tek kullanıcılı, macOS üzerinde çalışan bir ders arşivi: her dersi tarihi, akademisyeni, komitesi ve konu etiketleriyle kaydeder; aynı veriyi takvim, akademisyen, komite ve etiket açısından gösterir; derse ait PDF'leri iCloud klasöründen bulup bağlar.

Kapsam içinde:

- Ders kaydı oluşturma, düzenleme, silme
- Akademisyen, komite ve etiketlere göre filtreleme ve listeleme
- Aylık takvim ve gün detayı
- Diskteki PDF'leri derse bağlama, uygulamadan açma
- Hocanın slaytı ile kendi notunu ayrı tutma
- Serbest metin arama

Kapsam dışında (şimdilik):

- Giriş ekranı, kullanıcı hesabı, çoklu kullanıcı
- Sunucu, web arayüzü, iPad uygulaması
- Dosyaların uygulama içine kopyalanması — dosyalar iCloud klasöründe kalır, uygulama yalnızca yollarını tutar
- Ders programından otomatik içe aktarma

## Veri modeli

Beş varlık var. Merkezde `Lecture` duruyor, diğer dördü ona bağlanıyor.

| Varlık | Alanlar | İlişkiler |
| --- | --- | --- |
| Lecture | title, date, startTime, endTime, notes, createdAt | instructor (1), committee (1), tags (çoklu), files (çoklu) |
| Instructor | name, title, department, email | lectures (çoklu, ters yön) |
| Committee | name, startDate, endDate, colorHex | lectures (çoklu, ters yön) |
| Tag | name, colorHex | lectures (çoklu, çift yönlü) |
| LectureFile | fileName, bookmarkData, kind, addedAt | lecture (1, ters yön) |

İlişki kuralları:

- Bir dersin bir akademisyeni ve bir komitesi olur; ikisi de boş bırakılabilir.
- Bir dersin birden çok etiketi olur, bir etiket birden çok derste kullanılır.
- Bir dersin birden çok dosyası olur; her dosya tek bir derse aittir.
- Akademisyen veya komite silinirse dersler silinmez, alan boşalır. Ders silinirse ona bağlı dosya kayıtları silinir — diskteki dosyaya dokunulmaz.

`LectureFile.kind` üç değerli bir enum: `slide` (hocanın verdiği asıl dosya), `note` (kendi çıkardığın not), `other`. Ekranda ayrı başlıklar altında gruplanır.

`bookmarkData` düz bir dosya yolu değil, macOS'un güvenlik kapsamlı yer imi. Sebebi şu: kullanıcı bir dosyayı seçtiğinde uygulama ona erişim izni kazanır, ama uygulama kapanınca bu izin düşer. Yer imi izni kalıcı kılar ve dosya yeniden adlandırılıp taşınsa bile çoğu durumda takip eder.

## Klasör düzeni ve dosya eşleştirme

Dosyalar iCloud Drive içinde, uygulamanın dışında durur. Önerilen yapı:

```
~/Library/Mobile Documents/com~apple~CloudDocs/MED/
  Komite I/
    Biyofizik/
      2026-10-01 | Basic Principles in Biophysics.pdf
      2026-10-01 | Basic Principles in Biophysics — notlarım.pdf
    Tıbbi Biyoloji/
  Komite II/
```

Bu yapı iPad'deki Dosyalar uygulamasından da aynen görünür. Goodnotes'tan dışa aktardığın not doğru alt klasöre düşerse Mac'te kendiliğinden belirir.

Dosya adı kuralı: `YYYY-MM-DD | Ders adı.pdf`. İçinde `not` veya `notlarım` geçen dosyalar `note` türü sayılır, kalanı `slide`.

Uygulama dosyaları iki yoldan bağlar:

1. **Elle** — ders detayında "Dosya ekle" ile seçersin. Her zaman çalışır, kural gerektirmez.
2. **Otomatik tarama** — kök klasörü bir kez seçersin, uygulama alt klasörleri gezip dosya adındaki tarihi ve ders adını okur, eşleşen derse bağlar. Eşleşme bulunamayan dosyaları ayrı bir listede gösterir, oradan elle bağlarsın.

Tarama okuma amaçlıdır: dosya taşımaz, adını değiştirmez, silmez.

Eşleştirme mantığı: önce tarih, sonra ders adı. Ders adı karşılaştırması büyük/küçük harf ve noktalama farklarını yok sayar, Türkçe karakterleri normalleştirir. Aynı güne birden çok ders denk gelirse ad benzerliği en yüksek olana bağlar; eşik altında kalırsa bağlamaz, eşleşmeyenler listesine atar.

## Ekranlar

Solda kalıcı bir kenar çubuğu, sağda seçilen bölümün içeriği. Kenar çubuğu başlıkları: Takvim, Dersler, Akademisyenler, Komiteler, Etiketler.

| Ekran | Ne görünür | Ne yapılır |
| --- | --- | --- |
| Takvim | Aylık ızgara; ders olan günler komite rengiyle işaretli | Güne tıkla, o günün dersleri sağda listelensin; derse tıkla, detaya git |
| Dersler | Tüm dersler, tarihe göre tersten sıralı | Akademisyen, komite, etikete göre filtrele; ara; yeni ders ekle |
| Ders detayı | Başlık, tarih, saat, akademisyen, komite, etiketler, notlar, dosyalar | Alanları düzenle, etiket ekle/çıkar, dosya bağla, dosyayı aç |
| Akademisyen detayı | Ad, unvan, bölüm; verdiği derslerin tarih sıralı listesi | Derse git; akademisyen bilgisini düzenle |
| Komite detayı | Ad, tarih aralığı; içindeki dersler, konuya göre gruplanabilir | Derse git; komiteyi düzenle |
| Etiket detayı | Etiket adı; o etiketi taşıyan tüm dersler | Derse git; etiketi yeniden adlandır veya birleştir |

Ders detayında dosyalar üç başlık altında gruplanır: Slaytlar, Notlarım, Diğer. Her satırda dosya adı ve küçük bir önizleme ikonu olur; tıklayınca QuickLook ile uygulama içinde açılır, Cmd tıklayınca Finder'da gösterilir.

Arama kutusu ders adı, akademisyen adı, etiket ve not metninde birden arar. Sonuçlar tür ikonuyla ayrılır.

Yeni ders eklerken akademisyen ve komite alanları tamamlamalı açılır liste olur — yazmaya başlayınca mevcut kayıtlar süzülür, listede yoksa oracıkta yeni kayıt açılır. Etiket alanı da aynı şekilde çalışır, böylece aynı konu için farklı yazımlar birikmez.

## Teknik seçimler

| Konu | Seçim | Gerekçe |
| --- | --- | --- |
| Arayüz | SwiftUI | Tek dosyada hem ekran hem mantık; Xcode önizlemesiyle hızlı dönüş |
| Veri | SwiftData | Model sınıflarını `@Model` ile tanımlayıp bırakıyorsun; şema, sorgu ve kayıt arka planda hallediliyor |
| Senkron | Şimdilik kapalı | CloudKit tek satırla açılıyor; iPad'e geçmek istediğinde aç |
| Dosya erişimi | Güvenlik kapsamlı yer imi | Sandbox altında kalıcı dosya erişiminin tek yolu |
| Önizleme | QuickLook (`QLPreviewController`) | PDF'i uygulamadan çıkmadan göstermek için hazır bileşen |
| Hedef | macOS 14 veya üstü | SwiftData bu sürümle geldi |

İki noktada dikkat gerekiyor.

**Sandbox ve dosya izinleri.** Uygulama varsayılan olarak kendi kutusunda çalışır ve iCloud klasörünü göremez. Xcode'da Signing & Capabilities sekmesinden App Sandbox içindeki "User Selected File" iznini okuma-yazma yapman ve güvenlik kapsamlı yer imi kullanman gerekiyor. Kullanıcı klasörü bir kez seçer, uygulama o yer imini saklar, her açılışta `startAccessingSecurityScopedResource` ile erişimi geri alır.

**Yedekleme.** SwiftData veritabanı uygulamanın kendi konteynerinde durur. Time Machine onu kapsar, ama kazara silmeye karşı uygulamaya basit bir dışa aktarma koymak iyi olur: tüm kayıtları JSON olarak diske yazan tek bir menü komutu yeterli.

## Geliştirme sırası

Hepsini tek seferde isteme. Her aşamayı çalıştırıp gördükten sonra bir sonrakine geç — hata ayıklaması çok daha kolay olur.

1. **Veri modeli ve ders listesi.** Beş `@Model` sınıfı, ders ekleme formu, basit bir liste. Burada arayüz çirkin olsun, önemli değil; kayıt tutuyor mu ona bak.
2. **Ders detayı ve düzenleme.** Alanları değiştirme, akademisyen ve komite seçme, etiket ekleme. Tamamlamalı açılır listeler bu aşamada gelsin.
3. **İlişkili görünümler.** Akademisyen, komite ve etiket detay ekranları. Veri modeli doğruysa bunlar birkaç satırlık iş.
4. **Takvim.** Aylık ızgara ve gün seçimi. En çok uğraştıran ekran bu, o yüzden veri oturduktan sonra.
5. **Dosya bağlama.** Önce elle seçme ve QuickLook ile açma. Yer imi mantığı burada devreye girer.
6. **Otomatik tarama.** Kök klasörü gezip dosya adlarından eşleştirme. En kırılgan parça, en sona bırak.
7. **Arama ve dışa aktarma.** Serbest metin arama, JSON yedeği.

İlk üç aşama bittiğinde uygulama zaten işe yarar durumda olur. Dördüncüden sonrası konfor.

## Başlangıç istemi

Aşağıdaki metni olduğu gibi kopyalayıp kullanacağın araca ver. Birinci aşamayı bitirdiğinde "şimdi 2. aşama" diyerek devam et.

```markdown
macOS için SwiftUI ve SwiftData kullanan, tek kullanıcılı bir ders arşivi uygulaması yazıyoruz.
Hedef macOS 14+. Xcode projesi zaten açık.

VERİ MODELİ (SwiftData @Model):
- Lecture: title, date, startTime, endTime, notes, createdAt
  → instructor (Instructor?, tekil), committee (Committee?, tekil),
    tags ([Tag], çoklu), files ([LectureFile], çoklu, cascade silme)
- Instructor: name, title, department, email → lectures (ters ilişki)
- Committee: name, startDate, endDate, colorHex → lectures (ters ilişki)
- Tag: name, colorHex → lectures (çift yönlü çoklu)
- LectureFile: fileName, bookmarkData (Data), kind (enum: slide/note/other),
  addedAt → lecture (ters ilişki)

KURALLAR:
- Akademisyen veya komite silinince dersler silinmez, alan nil olur.
- Ders silinince LectureFile kayıtları silinir, diskteki dosyaya dokunulmaz.
- Dosyalar uygulamaya kopyalanmaz; yalnızca güvenlik kapsamlı yer imi saklanır.

ŞU AN SADECE 1. AŞAMAYI İSTİYORUM:
Beş model sınıfını yaz, ModelContainer kurulumunu yap, ve şunları içeren
asgari bir arayüz ver: ders listesi (tarihe göre tersten sıralı) ve
yeni ders ekleme formu. Akademisyen/komite/etiket seçimi bu aşamada
basit bir Picker olabilir. Arayüz sade olsun.

Kod yazarken:
- Her dosyayı tam yolu ve adıyla ver, parça parça değil.
- Xcode'da hangi dosyayı nereye ekleyeceğimi açıkça söyle.
- Sandbox veya izin ayarı gerekiyorsa adım adım anlat.
- Türkçe açıkla, kod ve değişken adları İngilizce olsun.
```

Sonraki aşamalarda aynı kalıbı kullan: ne istediğini tek cümleyle yaz, sonra "sadece bu aşamayı istiyorum" de. Model bir kerede her şeyi yazmaya kalkarsa kod şişer ve hata bulmak zorlaşır.
