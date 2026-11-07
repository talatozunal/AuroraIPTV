# Aurora IPTV (tvOS)

iOS sürümündeki tüm özellikler Apple TV'ye uyarlandı.

## Açma / çalıştırma
1. `AuroraIPTVTV.xcodeproj` dosyasını açın. Xcode, VLC paketini (`koombea/vlckit-spm`) kendisi indirir; ilk açılışta uzun sürebilir ("Resolving Package Graph" bitene kadar bekleyin).
2. Hedef olarak bir **Apple TV** (cihaz veya Simulator) seçip çalıştırın.
3. **Ayarlar → Playlist Ekle** ile M3U veya Xtream Codes hesabı ekleyin.

> VLC paketi sorun çıkarırsa: proje ayarlarında Package Dependencies sekmesinden `vlckit-spm` paketini kaldırabilirsiniz. Uygulama yine derlenir; yalnızca MKV/AVI film ve ham `.ts` yayınlar oynatılamaz.

## Özellikler
- **Playlistler:** M3U ve Xtream tek listede (rozetli). Satıra basınca Yenile / Devre Dışı / Kaldır menüsü açılır. Yükleme sonucu (kanal-film-dizi sayısı veya hata) satırda görünür. Uygulama açılışında kayıtlı playlist'ler otomatik yüklenir.
- **Kategoriler (dikey liste):** Solda bölüm başlıklı kategori listesi, sağda seçili kategorinin ızgarası.
  - Canlı TV: **Türkiye** bölümünde sağlayıcının kendi TR grupları, adlarıyla ve şu sırayla: HEVC, ULUSAL, UHD, beIN SPORTS, beIN FEED / P+, S SPORT, SPOR (genel spor grubu kanal adına göre TRT SPOR, TİVİBU SPOR, EXXEN SPOR, SMART SPOR, A SPOR, EUROSPORT olarak ayrılır), HABER, SİNEMA & DİZİ / 7/24 / NETFLIX SALON grupları, BELGESEL, ÇOCUK, DİNİ, YEREL, MÜZİK… Aynı sıradaki gruplar sağlayıcının kendi sırasını korur. Ardından **Spor**, **Haber**, **Film & Dizi** bölümlerinde yabancı gruplar (ör. NBA LEAGUE PASS), en sonda **Ülkeler** (Almanya, İngiltere, ABD… A-Z; tanınmayanlar "Diğer"). Kanallar kategori içinde sağlayıcının sırasında kalır ("Önerilen"); A-Z / Z-A düğmesiyle sıralanabilir. Sol listenin başında ★ Favoriler ve Son İzlenenler bulunur.
  - Film ve dizilerde TR başta, ardından platformlar (Netflix, Disney+…).
- **Üst çubuk:** Sekmeler solda; sıralama düğmesi (Önerilen → A-Z → Z-A) ve **arama simgesi** sağda, aynı hizada. Arama alanı varsayılan olarak görünmez; simgeye basınca arama sayfası açılır.
- **Odak görünümü:** Bir kart, kategori veya düğmeye odaklanınca sistemin beyaz plakası yerine vurgu renkli çerçeve ve hafif büyüme kullanılır; yazılar her zaman okunur.
- **Tema:** Aurora (kuzey ışıkları) teması: mavi-turkuaz-mor geçişli arka plan, nane yeşili vurgu.
- **Yetişkin içeriği gizle:** Ayarlar'da açılıp kapanır (varsayılan: açık). Kategori/kanal adında 18+, adult, xxx gibi ifadeler geçen içerikleri listelerden, aramadan, favorilerden ve geçmişten gizler.
- **Favoriler / Son izlenenler:** Kart üzerinde **uzun basış** (Select tuşunu basılı tutun) → "Favorilere Ekle". Dizi ayrıntı ekranında düğme var. **Kütüphane** sekmesinde Favoriler ve Son İzlenenler listelenir; kaydı kaldırmak için üzerine uzun basın.
- **Diziler:** Xtream dizilerinde sezon/bölüm ekranı.
- **UHD / 4K / HEVC kanallar:** Önce VLC ile ham TS olarak açılır; olmazsa HLS denenir. Hata ekranı hangi yöntemin neden başarısız olduğunu listeler.
- **Oynatma:** Canlı yayınlar HLS (.m3u8) olarak açılır. MKV/AVI/ham TS için VLC. Yerleşik oynatıcıda standart Apple TV kumanda arayüzü; VLC'de ▶︎⏸ duraklat, ◀︎ ▶︎ 10 sn geri/ileri, Menü kapatır.

## Notlar
- tvOS'ta UserDefaults ~500 KB ile sınırlıdır: en fazla 300 favori ve 40 geçmiş kaydı tutulur (en eskiler silinir).
- Playlist bilgilerini Apple TV'de yazmak zahmetlidir; iPhone'unuz Apple TV'ye yakınsa Apple TV klavye bildirimi ile yazabilirsiniz.
