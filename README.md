# Aurora IPTV

iOS, macOS ve tvOS için SwiftUI ile geliştirilmiş IPTV oynatıcı ailesi.

> **Önemli:** Bu depoda hiçbir playlist, sağlayıcı adresi, kullanıcı adı veya şifre bulunmaz.
> Uygulamalar boş kurulur; içerik yalnızca kullanıcı kendi M3U listesini ya da Xtream Codes
> hesabını eklediğinde yüklenir.

## Platformlar

| Platform | Klasör | Dağıtım |
| --- | --- | --- |
| iOS 16+ (iPhone / iPad) | [`iOS/`](iOS) | Kaynak kod — cihaza kurmak için Xcode ile imzalama gerekir |
| tvOS 17+ (Apple TV) | [`tvOS/`](tvOS) | Kaynak kod — cihaza kurmak için Xcode ile imzalama gerekir |
| macOS 14+ | [`macOS/`](macOS) | İmzalı uygulama — [Releases](https://github.com/talatozunal/AuroraIPTV/releases) |

## Özellikler

- Canlı TV, filmler ve diziler
- EPG desteği
- M3U ve Xtream Codes hesabı ekleme
- Kategori gruplama, arama, favoriler ve son izlenenler
- VLCKit ile MKV / AVI / ham TS oynatma (iOS ve tvOS'ta Swift Package olarak)
- UHD / 4K / HEVC kanallarda önce ham TS (VLC), ardından HLS denemesi
- Aurora (kuzey ışıkları) teması
- Yetişkin içeriği gizleme
- PiP desteği (desteklenen iOS cihazlarında)

## Derleme

### iOS

1. `iOS/AuroraIPTV.xcodeproj` dosyasını Xcode ile açın.
2. Xcode, `koombea/vlckit-spm` paketini kendisi indirir (ilk açılışta sürebilir).
3. Kendi Apple Developer hesabınızla imzalayıp bir iPhone / iPad veya Simulator seçerek çalıştırın.

### tvOS

1. `tvOS/AuroraIPTVTV.xcodeproj` dosyasını Xcode ile açın.
2. `koombea/vlckit-spm` paketinin çözülmesini bekleyin.
3. Kendi hesabınızla imzalayıp bir Apple TV veya Simulator seçerek çalıştırın.

### macOS

`macOS/` klasöründeki README'ye bakın. İmzalı uygulama Releases bölümünden indirilebilir.

## Kullanım

1. Uygulamayı açın.
2. **Ayarlar → Playlist Ekle** bölümüne gidin.
3. M3U adresinizi veya Xtream Codes sunucu / kullanıcı / şifre bilgilerinizi girin.

Playlist bilgileri yalnızca cihazın kendi yerel depolamasında tutulur; bu depoya veya
uygulama paketine dahil edilmez.

## Üçüncü taraf bileşenler

VLCKit (LGPL-2.1) kullanılmaktadır. Ayrıntılar için
[`THIRD_PARTY_NOTICES.txt`](THIRD_PARTY_NOTICES.txt) ve
[`VLCKit-COPYING.txt`](VLCKit-COPYING.txt) dosyalarına bakın.

## Lisans

[MIT](LICENSE)
