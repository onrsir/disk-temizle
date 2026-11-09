# Disk Temizle (Disk Cleaner)

[Türkçe](#türkçe) · [English](#english)

## Türkçe

Geliştirici Mac'leri için küçük bir SwiftUI disk temizleme uygulaması. Diski tarar, gereksiz yer kaplayanları gruplar halinde boyutlarıyla listeler, tıklayınca siler. Arayüz Türkçe ve İngilizce (sağ üstten değiştirilir, ilk açılışta sistem dili kullanılır).

Taradıkları:
- **Paket ve araç cache'leri**: `~/Library/Caches`, loglar, Xcode DerivedData/Previews, Maven, Gradle, npm, Yarn, pnpm, Bun, pip, uv, Conda, Go modülleri, Cargo, NuGet, Composer, Dart pub, Hugging Face, Whisper, Puppeteer, VS Code/Cursor
- **Proje build çıktıları** (proje klasörlerinde): frontend (`node_modules`, `.next`, `.nuxt`, `.turbo`, `.svelte-kit`, `.angular`, `.parcel-cache`, `dist`, `build`), backend (Maven/Rust/sbt `target`, Gradle `build` ve `.gradle`, .NET `bin`/`obj`, Python `.venv`, `__pycache__`, test cache'leri), mobil (Flutter `build`, `.dart_tool`, `Pods`, Expo). `target`, `build`, `dist`, `bin` gibi genel isimler sadece yanında proje dosyası (`pom.xml`, `Cargo.toml`, `build.gradle`, `package.json`, `.csproj` …) varsa listelenir.
- **Docker**: kullanılmayan imaj, container ve build cache (volume'lara dokunmaz; Docker açık olmalı)
- **iOS simülatörleri**: cihazın tamamı ya da sadece cache'i
- **Android**: emülatörler (AVD) ve SDK system image'ları
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
- **Package and tool caches**: `~/Library/Caches`, logs, Xcode DerivedData/Previews, Maven, Gradle, npm, Yarn, pnpm, Bun, pip, uv, Conda, Go modules, Cargo, NuGet, Composer, Dart pub, Hugging Face, Whisper, Puppeteer, VS Code/Cursor
- **Project build outputs** (in your project folders): frontend (`node_modules`, `.next`, `.nuxt`, `.turbo`, `.svelte-kit`, `.angular`, `.parcel-cache`, `dist`, `build`), backend (Maven/Rust/sbt `target`, Gradle `build` and `.gradle`, .NET `bin`/`obj`, Python `.venv`, `__pycache__`, test caches), mobile (Flutter `build`, `.dart_tool`, `Pods`, Expo). Generic names like `target`, `build`, `dist`, `bin` are only listed when a project file (`pom.xml`, `Cargo.toml`, `build.gradle`, `package.json`, `.csproj`, …) sits next to them.
- **Docker**: unused images, containers and build cache (volumes are kept; Docker must be running)
- **iOS simulators**: the whole device or only its cache
- **Android**: emulators (AVDs) and SDK system images
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
