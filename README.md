# Disk Temizle (Disk Cleaner)

[Türkçe](#türkçe) · [English](#english)

## Türkçe

Geliştirici Mac'leri için küçük bir SwiftUI disk temizleme uygulaması. Diski tarar, gereksiz yer kaplayanları gruplar halinde boyutlarıyla listeler, tıklayınca siler. Arayüz Türkçe ve İngilizce (sağ üstten değiştirilir, ilk açılışta sistem dili kullanılır).

Taradıkları:
- **Cache'ler**: `~/Library/Caches`, Xcode DerivedData, Gradle, npm, pnpm, uv, Hugging Face, Whisper, Puppeteer
- **Build çıktıları** (proje klasörlerinde): `.turbo`, `.next`, `node_modules`, `Pods`, Flutter `build/`
- **iOS simülatörleri**: cihazın tamamı ya da sadece cache'i
- **Android emülatörleri** (AVD)
- **Xcode**: Archives, iOS DeviceSupport
- **Claude**: ekran görüntüleri/videolar, 30 günden eski konuşmalar, VM imajı, uygulama cache'i
- **Unity** projelerinin `Library` klasörleri
- **Downloads**: 200 MB üstü öğeler

Proje klasörleri varsayılan olarak ev dizinindeki yaygın klasörlerdir (`Developer`, `Projects`, `code`, `dev`, `src`, `workspace`, `repos` vb.); uygulamadaki **Proje klasörleri** butonundan değiştirilir.

Silme kalıcıdır (çöp kutusuna gitmez), her silmeden önce onay sorulur. Sadece ev dizini altındaki yollar silinir.

### Kurulum

[Releases](https://github.com/onrsir/disk-temizle/releases) sayfasından `Disk-Temizle.zip` dosyasını indirip açın. Uygulama imzasız olduğu için ilk açılışta sağ tık → **Aç** deyin.

### Derleme

macOS 14+ ve Xcode komut satırı araçları gerekir.

```bash
./build.sh
open "build/Disk Temizle.app"
```

Arayüz açmadan tarama sonucu: `"build/Disk Temizle.app/Contents/MacOS/DiskTemizle" --dump --lang tr`

## English

A small SwiftUI disk cleanup app for developer Macs. It scans the disk, lists what takes up space in groups with sizes, and deletes it with a click. The UI is in Turkish and English (switch at the top right; the system language is used on first launch).

What it scans:
- **Caches**: `~/Library/Caches`, Xcode DerivedData, Gradle, npm, pnpm, uv, Hugging Face, Whisper, Puppeteer
- **Build outputs** (in your project folders): `.turbo`, `.next`, `node_modules`, `Pods`, Flutter `build/`
- **iOS simulators**: the whole device or only its cache
- **Android emulators** (AVDs)
- **Xcode**: Archives, iOS DeviceSupport
- **Claude**: screenshots/videos, conversations older than 30 days, VM image, app cache
- **Unity** project `Library` folders
- **Downloads**: items over 200 MB

By default the project folders are the common ones in your home folder (`Developer`, `Projects`, `code`, `dev`, `src`, `workspace`, `repos`, …); change them with the **Project folders** button.

Deletion is permanent (nothing goes to the Trash) and every delete asks for confirmation first. Only paths inside your home folder are deleted.

### Install

Download `Disk-Temizle.zip` from [Releases](https://github.com/onrsir/disk-temizle/releases) and unzip it. The app is not notarized, so on first launch right-click it and choose **Open**.

### Build

Requires macOS 14+ and the Xcode command line tools.

```bash
./build.sh
open "build/Disk Temizle.app"
```

Scan without the UI: `"build/Disk Temizle.app/Contents/MacOS/DiskTemizle" --dump --lang en`
