# MED

*[English / İngilizce](README.en.md)*

Tıp fakültesi dersleri için arşiv. macOS uygulaması — hesap yok, sunucu yok,
abonelik yok, reklam yok. Her şey senin Mac'inde kalıyor.

Tek bir soruyu hızlı cevaplıyor: **o ders neydi, slaytı nerede?**

## Ne yapıyor

- **Oturumlar** — her ders için bir kayıt: o günün konusu, dersi, hocası,
  komitesi, etiketleri, notları.
- **Okul programı hazır** — dokuz ders, 40'ar dakika. Tek tıkla saat seçiyorsun,
  iki saat çarkıyla uğraşmıyorsun. Üst üste iki ders süren bir konu tek blok
  olarak görünüyor.
- **Teorik / Pratik / Sınav** — pratik ve sınav rozetli, listede göze çarpıyor.
- **Takvim** — aylık ızgara, Apple Calendar tarzı haftalık görünüm (hücreler
  ders renginde), ve günü program gibi okuyan gün görünümü.
- **Aynı konunun iki dersi** tek satırda, (1/2) diye numaralı, ve **slaytları
  ortak**: aradaki teneffüs ikinci bir slayt dağıtmıyor.
- **Arama ve filtre** — ders, hoca, komite, tür, ve **"slaytı eksik olanlar"**.
- **Dosyalar** — elindeki PDF'leri bağlıyorsun, boşluk tuşuyla önizliyorsun,
  Finder'da açıyorsun.
- **Klasör tarama** — klasörü gösteriyorsun, hangi dosyanın hangi derse ait
  olduğunu kendisi buluyor (dosya adındaki tarih, klasör, konu benzerliği).
  Kesin / zayıf / eşleşmedi diye üç listeye ayırıyor, sen onaylıyorsun.
- **Çıkmış sınavlar** — komite altında, yıl ve dil bilgisiyle.
- **Türkçe ve İngilizce** — Ayarlar'dan anında değişiyor.

## Kurulum

[Releases sayfasından](../../releases) `MED.dmg` indir, aç, **MED**'i
Applications klasörüne sürükle.

İlk açılışta macOS **"geliştirici doğrulanamadı"** diyecek. Uygulama imzasız
dağıtıldığı için normal — kaynak kodun tamamı burada, isteyen bakar. Açmak
için:

1. **Sistem Ayarları → Gizlilik ve Güvenlik**'i aç
2. Aşağıya in, MED ile ilgili satırı bul
3. **"Yine de Aç"** düğmesine bas

Bir kez yapılıyor, sonra normal uygulama gibi açılıyor.

## Dosyalarına ne oluyor

**Hiçbir şey.** Uygulama dosyalarının *yerini* saklıyor, kopyasını tutmuyor.
Hiçbir dosyayı kopyalamıyor, taşımıyor, adını değiştirmiyor, silmiyor. Bir
dosyayı dersten kaldırmak, o dosyanın nerede olduğunu unutmak demek — dosya
yerinde kalıyor.

Ayarlar'dan (⌘,) bir **kök klasör** seçersen, o klasörün altındaki dosyalar
klasöre göre kaydediliyor: klasörü taşısan ya da adını değiştirsen de bağlar
kopmuyor.

Başka bir yere taşıdığın dosyanın kaydı boşa düşüyor. Konular ekranındaki
**Dosya işlemleri** menüsü böyle kayıtların hepsini listeliyor ve dosyanın
yeni yerini göstermene izin veriyor.

## Verin nerede

Tek bir dosyada, Mac'inde. Ayarlar (⌘,) yerini gösteriyor ve Finder'da açıyor
— **düzenli kopyalaman gereken dosya o.** iCloud klasörüne ya da Time
Machine'e bırakman yeterli.

Dosya menüsünden (⌘⇧E) arşivin tamamını okunabilir bir JSON dosyasına
aktarabilirsin: ne var ne yok görmek ve veriyi başka bir yere taşımak için.

## Kendi okuluna uyarlamak

Ders saatleri şu an koda yazılı: dokuz ders, 40'ar dakika, 08.50'de başlıyor.
Senin okulun farklıysa şimdilik `MED/Support/LessonSlot.swift` dosyasındaki
tabloyu değiştirmek gerekiyor — bunu Ayarlar'dan yapılabilir hale getirmek
yapılacaklar listesinde.

İyi haber: oturumlar ders *numarası* değil gerçek saatleri sakladığı için o
tabloyu değiştirmek hiçbir kaydı bozmuyor.

## Kodu okumak / katkı

Mimari kararlar, SwiftData tuzakları ve her şeyin neden böyle olduğu
[docs/GELISTIRME.md](docs/GELISTIRME.md) içinde.

## Lisans

**PolyForm Noncommercial 1.0.0** — [LICENSE](LICENSE).

Kullanabilirsin, inceleyebilirsin, değiştirebilirsin, değiştirdiğin hâlini
dağıtabilirsin: kendi dersin için, arkadaşların için, eğitim ve araştırma
için, bir üniversite ya da dernek için. **Ticari kullanım yok** — satmak,
erişimi satmak, ücretli sürüm yapmak, reklam koymak, satılan bir şeyin içine
koymak olmuyor.

Bu projenin amacı, tıp öğrencisinin kendi derslerinin arşivi için para
ödemek zorunda olmaması. Geliştirip başkasına ulaştırmak tam olarak istenen
şey; ücret alma yolu bulmak değil.

Ticari bir kullanım düşünüyorsan önce sor.

Türker Akın & Claude tarafından yapıldı.
