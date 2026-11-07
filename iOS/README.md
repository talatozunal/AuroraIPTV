# Aurora IPTV (iOS)

iOS 16+ (iPhone/iPad) için Aurora IPTV benzeri SwiftUI uygulaması. Android projesindeki yapıya paralel olarak tasarlanmıştır.

## Özellikler
- Canlı Yayınlar / Filmler / Diziler (Vod/Series)
- EPG
- M3U / Xtream Codes entegrasyonu
- Oynatıcı (AVPlayer)
- Ayarlar (Dil, Tema vb.)
- PiP desteği (desteklenen cihazlarda)

## Gereksinimler
- Xcode 15+ 
- iOS 16.0+
- Swift 5.9+

## Kurulum
1. `AuroraIPTV.xcodeproj` dosyasını Xcode ile açın
2. Hedef cihazı seçin ve çalıştırın

## Not
Bu proje, Android projesindeki mantığa sadık kalarak SwiftUI ile yeniden yazılmıştır.

## Oynatma notları (önemli)

- **Canlı TV:** Xtream canlı yayınları artık `.m3u8` (HLS) olarak açılır. iOS'un AVPlayer'ı ham `.ts` akışını oynatamaz (siyah ekran sebebi buydu).
- **Diziler:** Dizi kartına dokununca sezon/bölüm listesi açılır (`get_series_info`).
- **Filmler / MKV, AVI, ham TS:** iOS bu biçimleri yerleşik olarak açamaz ("cannot open"). Bunlar için VLCKit ekleyin:
  1. Xcode → File → Add Package Dependencies…
  2. `https://github.com/koombea/vlckit-spm` (sürüm 3.6.0 ve üstü) → **VLCKitSPM** ürününü `AuroraIPTV` hedefine ekleyin.
  3. Gerçek cihazda veya Simulator'da çalıştırın. Kod `canImport` ile otomatik algılar; başka değişiklik gerekmez.
  (CocoaPods ile `pod 'MobileVLCKit'` de çalışır; o zaman `.xcworkspace` açın.)
- `PlayerResourceLoader.swift` artık kullanılmıyor (tüm dosyayı belleğe indiriyordu). İsterseniz projeden silebilirsiniz.
