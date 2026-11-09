# Disk Temizle

Geliştirici Mac'leri için küçük bir SwiftUI disk temizleme uygulaması. Diski tarar, gereksiz yer kaplayanları gruplar halinde boyutlarıyla listeler, tıklayınca siler.

Taradıkları:
- **Cache'ler**: `~/Library/Caches`, Xcode DerivedData, Gradle, npm, pnpm, uv, Hugging Face, Whisper, Puppeteer
- **Build çıktıları** (`~/IdeaProjects` altında): `.turbo`, `.next`, `node_modules`, `Pods`, Flutter `build/`
- **iOS simülatörleri**: cihazın tamamı ya da sadece cache'i
- **Android emülatörleri** (AVD)
- **Xcode**: Archives, iOS DeviceSupport
- **Claude**: ekran görüntüleri/videolar, 30 günden eski konuşmalar, VM imajı, uygulama cache'i
- **Unity** projelerinin `Library` klasörleri
- **Downloads**: 200 MB üstü öğeler

Silme kalıcıdır (çöp kutusuna gitmez), her silmeden önce onay sorulur. Sadece ev dizini altındaki yollar silinir.

## Derleme

macOS 14+ ve Xcode komut satırı araçları gerekir.

```bash
./build.sh
open "build/Disk Temizle.app"
```

Arayüz açmadan tarama sonucunu görmek için:

```bash
"build/Disk Temizle.app/Contents/MacOS/DiskTemizle" --dump
```
