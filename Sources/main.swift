import SwiftUI
import AppKit

// MARK: - Helpers

let H = NSHomeDirectory()
let fm = FileManager.default

// UI language: saved choice, otherwise the system language.
var lang = UserDefaults.standard.string(forKey: "lang")
    ?? (Locale.preferredLanguages.first?.hasPrefix("tr") == true ? "tr" : "en")
func L(_ tr: String, _ en: String) -> String { lang == "tr" ? tr : en }

func hp(_ s: String) -> String { H + "/" + s }

// Folders searched for build outputs and Unity projects: the user's choice, otherwise common dev folders that exist.
let commonRoots = ["Developer", "Projects", "IdeaProjects", "code", "dev", "src", "workspace", "repos", "GitHub", "Documents/GitHub"]
func projectRoots() -> [String] {
    UserDefaults.standard.stringArray(forKey: "roots") ?? commonRoots.map(hp).filter(exists)
}
func exists(_ p: String) -> Bool { fm.fileExists(atPath: p) }
func base(_ p: String) -> String { (p as NSString).lastPathComponent }
func rel(_ p: String) -> String { p.hasPrefix(H + "/") ? "~/" + p.dropFirst(H.count + 1) : p }
func fmt(_ b: Int64) -> String { ByteCountFormatter.string(fromByteCount: b, countStyle: .file) }
func lines(_ s: String) -> [String] { s.split(separator: "\n").map(String.init) }

func children(_ dir: String) -> [String] {
    ((try? fm.contentsOfDirectory(atPath: dir)) ?? [])
        .filter { $0 != ".DS_Store" && $0 != ".localized" }
        .sorted()
        .map { dir + "/" + $0 }
}

@discardableResult
func run(_ args: [String]) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = args
    // Apps opened from Finder get a minimal PATH; add Homebrew and /usr/local so docker, go etc. are found.
    var env = ProcessInfo.processInfo.environment
    env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
    p.environment = env
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return "" }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
}

// du is much faster than walking the tree with FileManager.
func diskSize(_ paths: [String]) -> Int64 {
    let ex = paths.filter(exists)
    var total: Int64 = 0
    for i in stride(from: 0, to: ex.count, by: 200) {
        for l in lines(run(["du", "-sk"] + ex[i..<min(i + 200, ex.count)])) {
            if let k = Int64(l.split(separator: "\t").first ?? "") { total += k * 1024 }
        }
    }
    return total
}

// "12.3GB (45%)" -> bytes. Docker uses decimal units.
func dockerSize(_ s: String) -> Int64 {
    let t = s.split(separator: " ").first.map(String.init) ?? ""
    for (u, m) in [("kB", 1e3), ("KB", 1e3), ("MB", 1e6), ("GB", 1e9), ("TB", 1e12), ("B", 1.0)] where t.hasSuffix(u) {
        return Int64((Double(t.dropLast(u.count)) ?? 0) * m)
    }
    return 0
}

func has(_ dir: String, _ files: [String]) -> Bool { files.contains { exists(dir + "/" + $0) } }
func hasExt(_ dir: String, _ exts: [String]) -> Bool { children(dir).contains { p in exts.contains { p.hasSuffix($0) } } }

// Folder names that can be build output or cache inside a project.
let buildNames = ["node_modules", ".next", ".nuxt", ".turbo", ".parcel-cache", ".svelte-kit", ".angular", ".expo", "Pods",
                  "target", "build", "dist", ".gradle", "bin", "obj", ".dart_tool", "venv", ".venv", "__pycache__",
                  ".pytest_cache", ".mypy_cache", ".ruff_cache", ".tox", "DerivedData"]

// Label for a found folder, or nil when it is not generated output (generic names need a marker file next to them).
func classify(_ path: String) -> String? {
    let parent = (path as NSString).deletingLastPathComponent
    let gradle = ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"]
    switch base(path) {
    case "node_modules": return L("node_modules (paket kurulumuyla geri gelir)", "node_modules (restored by package install)")
    case ".next": return "Next.js build"
    case ".nuxt": return "Nuxt build"
    case ".turbo": return "Turbo cache"
    case ".parcel-cache": return "Parcel cache"
    case ".svelte-kit": return "SvelteKit build"
    case ".angular": return "Angular cache"
    case ".expo": return "Expo cache"
    case "Pods": return L("CocoaPods (pod install ile geri gelir)", "CocoaPods (restored by pod install)")
    case ".dart_tool": return "Dart tool cache"
    case "DerivedData": return "Xcode DerivedData"
    case ".pytest_cache", ".mypy_cache", ".ruff_cache", ".tox": return L("Python test/lint cache'i", "Python test/lint cache")
    case "venv", ".venv":
        return exists(path + "/pyvenv.cfg") ? L("Python sanal ortamı (yeniden kurulur)", "Python virtualenv (reinstall to restore)") : nil
    case ".gradle": return has(parent, gradle) ? L("Gradle proje cache'i", "Gradle project cache") : nil
    case "target":
        if has(parent, ["pom.xml"]) { return "Maven target" }
        if has(parent, ["Cargo.toml"]) { return "Rust target" }
        if has(parent, ["build.sbt"]) { return "sbt target" }
        return nil
    case "build":
        if has(parent, gradle) { return "Gradle build" }
        if has(parent, ["pubspec.yaml"]) { return "Flutter build" }
        if has(parent, ["package.json"]) { return L("JS build çıktısı", "JS build output") }
        if has(parent, ["CMakeLists.txt", "setup.py", "pyproject.toml"]) { return "build" }
        return nil
    case "dist": return has(parent, ["package.json", "setup.py", "pyproject.toml"]) ? L("dist çıktısı", "dist output") : nil
    case "bin", "obj": return hasExt(parent, [".csproj", ".fsproj", ".vbproj"]) ? ".NET \(base(path))" : nil
    default: return nil
    }
}

// "com.apple.CoreSimulator.SimRuntime.iOS-26-1" -> "iOS 26.1"
func runtimeName(_ rt: String) -> String {
    let last = rt.split(separator: ".").last.map(String.init) ?? rt
    let parts = last.split(separator: "-")
    guard let first = parts.first else { return last }
    return "\(first) \(parts.dropFirst().joined(separator: "."))"
}

// MARK: - Model

struct CleanItem: Identifiable {
    let id = UUID()
    var name: String
    var detail = ""
    var paths: [String]
    var commands: [[String]] = []
    var fixedSize: Int64? = nil   // for items that are not plain folders (Docker)
    var size: Int64 = 0
    var selected = false
}

struct CleanSection: Identifiable {
    let id = UUID()
    let title: String
    let note: String
    let safe: Bool
    var minSize: Int64 = 10 << 20
    var items: [CleanItem]
    var total: Int64 { items.reduce(0) { $0 + $1.size } }
}

struct SimDevice: Decodable { let udid: String; let name: String; let state: String }
struct SimList: Decodable { let devices: [String: [SimDevice]] }

// MARK: - Scanner

enum Scanner {
    static func scan(progress: @escaping (String) -> Void) -> [CleanSection] {
        progress(L("Klasörler aranıyor…", "Looking for folders…"))
        var sections = discover()
        let snapshot = sections
        let refs = snapshot.indices.flatMap { s in snapshot[s].items.indices.map { (s, $0) } }
        var sizes = [Int64](repeating: 0, count: refs.count)
        let lock = NSLock()
        var done = 0
        DispatchQueue.concurrentPerform(iterations: refs.count) { i in
            let (s, j) = refs[i]
            let item = snapshot[s].items[j]
            let size = item.fixedSize ?? diskSize(item.paths)
            lock.lock(); sizes[i] = size; done += 1; let d = done; lock.unlock()
            progress(L("Boyutlar hesaplanıyor", "Measuring sizes") + " (\(d)/\(refs.count))")
        }
        for (i, (s, j)) in refs.enumerated() { sections[s].items[j].size = sizes[i] }
        for s in sections.indices {
            let min = sections[s].minSize
            sections[s].items = sections[s].items.filter { $0.size >= min }.sorted { $0.size > $1.size }
        }
        return sections.filter { !$0.items.isEmpty }
    }

    static func discover() -> [CleanSection] {
        let roots = projectRoots()

        let appSupport = hp("Library/Application Support")
        let caches: [(String, [String])] = [
            (L("Uygulama cache'leri", "App caches") + " (~/Library/Caches)", children(hp("Library/Caches"))),
            (L("Uygulama logları", "App logs") + " (~/Library/Logs)", children(hp("Library/Logs"))),
            ("Xcode DerivedData", children(hp("Library/Developer/Xcode/DerivedData"))),
            ("Xcode Previews", [hp("Library/Developer/Xcode/UserData/Previews")]),
            ("CoreSimulator cache", [hp("Library/Developer/CoreSimulator/Caches")]),
            ("Maven (~/.m2/repository)", [hp(".m2/repository")]),
            ("Gradle cache", [hp(".gradle/caches"), hp(".gradle/wrapper/dists")]),
            ("npm cache", [hp(".npm/_cacache"), hp(".npm/_npx")]),
            ("Yarn cache", [hp(".yarn/berry/cache"), hp(".cache/yarn")]),
            ("pnpm store", [hp("Library/pnpm/store"), hp(".local/share/pnpm/store"), hp(".pnpm-store")]),
            ("Bun cache", [hp(".bun/install/cache")]),
            ("uv (Python) cache", [hp(".cache/uv")]),
            ("pip cache", [hp(".cache/pip")]),
            (L("Conda paketleri", "Conda packages"),
             ["miniconda3", "anaconda3", "miniforge3", "opt/anaconda3", "opt/miniconda3"].map { hp($0 + "/pkgs") }),
            (L("Go modül cache'i", "Go module cache"), [hp("go/pkg/mod")]),
            ("Rust (cargo) registry", [hp(".cargo/registry"), hp(".cargo/git")]),
            (L("NuGet (.NET) paketleri", "NuGet (.NET) packages"), [hp(".nuget/packages")]),
            ("Composer (PHP) cache", [hp(".composer/cache"), hp(".cache/composer")]),
            ("Dart pub cache", [hp(".pub-cache/hosted"), hp(".pub-cache/git")]),
            (L("Hugging Face modelleri", "Hugging Face models"), [hp(".cache/huggingface")]),
            (L("Whisper modelleri", "Whisper models"), [hp(".cache/whisper")]),
            (L("Puppeteer tarayıcıları", "Puppeteer browsers"), [hp(".cache/puppeteer")]),
            (L("VS Code / Cursor cache'leri", "VS Code / Cursor caches"),
             ["Code", "Cursor", "Windsurf"].flatMap { app in
                 ["Cache", "CachedData", "CachedExtensionVSIXs", "Code Cache", "GPUCache"].map { appSupport + "/\(app)/\($0)" }
             }),
        ]

        var builds: [CleanItem] = []
        var pycache: [String] = []
        var nameExpr: [String] = []
        for (i, n) in buildNames.enumerated() { nameExpr += (i == 0 ? [] : ["-o"]) + ["-name", n] }
        // find with no start path would search the current directory.
        let found = roots.isEmpty ? [] : lines(run(["find"] + roots + ["-maxdepth", "7",
                               "(", "-name", ".git", "-o", "-name", "Library", ")", "-prune", "-o",
                               "-type", "d", "("] + nameExpr + [")", "-prune", "-print"]))
        for f in found {
            if base(f) == "__pycache__" { pycache.append(f); continue }
            if let label = classify(f) { builds.append(CleanItem(name: rel(f), detail: label, paths: [f])) }
        }
        if !pycache.isEmpty {
            builds.append(CleanItem(name: "Python __pycache__", detail: "\(pycache.count) " + L("klasör", "folders"), paths: pycache))
        }

        var docker: [CleanItem] = []
        let df = run(["docker", "system", "df", "--format", "{{.Type}}\t{{.Reclaimable}}"])
        if !df.isEmpty {
            let reclaim = lines(df).filter { !$0.hasPrefix("Local Volumes") }
                .reduce(Int64(0)) { $0 + dockerSize(String($1.split(separator: "\t").last ?? "")) }
            docker.append(CleanItem(name: L("Kullanılmayan imajlar, container'lar ve build cache", "Unused images, containers and build cache"),
                                    detail: "docker system prune -a · " + L("volume'lara dokunmaz", "volumes are kept"),
                                    paths: [], commands: [["docker", "system", "prune", "-af"]], fixedSize: reclaim))
        }

        var sims: [CleanItem] = []
        if let data = run(["xcrun", "simctl", "list", "devices", "-j"]).data(using: .utf8),
           let list = try? JSONDecoder().decode(SimList.self, from: data) {
            for (rt, devs) in list.devices {
                let os = runtimeName(rt)
                for d in devs {
                    let dir = hp("Library/Developer/CoreSimulator/Devices/" + d.udid)
                    guard exists(dir) else { continue }
                    let booted = d.state == "Booted"
                    sims.append(CleanItem(name: d.name,
                                          detail: os + (booted ? L(" · açık", " · running") : "") + L(" · cihazı tamamen sil", " · delete the whole device"),
                                          paths: [dir],
                                          commands: [["xcrun", "simctl", "shutdown", d.udid], ["xcrun", "simctl", "delete", d.udid]]))
                    if !booted {
                        sims.append(CleanItem(name: d.name + L(" — sadece cache", " — cache only"),
                                              detail: os + L(" · uygulamalar ve kayıtlar kalır", " · apps and data are kept"),
                                              paths: [dir + "/data/Library/Caches"]))
                    }
                }
            }
        }

        let avdRoot = hp(".android/avd")
        let inis = children(avdRoot).filter { $0.hasSuffix(".ini") }
        let avds = children(avdRoot).filter { $0.hasSuffix(".avd") }.map { avd -> CleanItem in
            let n = base(avd)
            let own = inis.filter { ((try? String(contentsOfFile: $0, encoding: .utf8)) ?? "").contains("/" + n) }
            return CleanItem(name: (n as NSString).deletingPathExtension, detail: L("Android emülatörü", "Android emulator"), paths: [avd] + own)
        }
        let images = hp("Library/Android/sdk/system-images")
        let sysImages = children(images).flatMap(children).flatMap(children).map {
            CleanItem(name: "system-image " + $0.dropFirst(images.count + 1),
                      detail: L("Android SDK · SDK Manager'dan yeniden indirilir", "Android SDK · re-download in SDK Manager"), paths: [$0])
        }

        var xcode = children(hp("Library/Developer/Xcode/Archives")).map { d -> CleanItem in
            let apps = Set(children(d).map { base($0).components(separatedBy: " ").first ?? "" }).sorted().joined(separator: ", ")
            return CleanItem(name: L("Arşiv ", "Archive ") + base(d), detail: apps, paths: [d])
        }
        xcode += children(hp("Library/Developer/Xcode/iOS DeviceSupport")).map {
            CleanItem(name: base($0), detail: L("iOS DeviceSupport (cihaz bağlanınca yeniden oluşur)", "iOS DeviceSupport (rebuilt when a device connects)"), paths: [$0])
        }

        let cp = hp(".claude/projects")
        let media = lines(run(["find", cp, "-type", "f", "(", "-iname", "*.png", "-o", "-iname", "*.jpg", "-o", "-iname", "*.jpeg",
                               "-o", "-iname", "*.webp", "-o", "-iname", "*.gif", "-o", "-iname", "*.mp4", "-o", "-iname", "*.mov",
                               "-o", "-iname", "*.webm", ")"]))
        let old = lines(run(["find", cp, "-mindepth", "2", "-maxdepth", "2", "-mtime", "+30", "-not", "-name", "memory"]))
        let cl = hp("Library/Application Support/Claude")
        let claude = [
            CleanItem(name: L("Ekran görüntüleri ve videolar", "Screenshots and videos"),
                      detail: "\(media.count) " + L("dosya", "files") + " · ~/.claude/projects", paths: media),
            CleanItem(name: L("30 günden eski konuşmalar", "Conversations older than 30 days"),
                      detail: "\(old.count) " + L("öğe · bu konuşmalara geri dönülemez", "items · these can no longer be resumed"), paths: old),
            CleanItem(name: L("Claude sanal makinesi (vm_bundles)", "Claude virtual machine (vm_bundles)"),
                      detail: L("Önce Claude'u kapat · gerekince yeniden iner", "Quit Claude first · re-downloaded when needed"), paths: [cl + "/vm_bundles"]),
            CleanItem(name: L("Claude uygulama cache'i", "Claude app cache"), paths: [cl + "/Cache", cl + "/Code Cache", cl + "/GPUCache"]),
        ]

        var unity: [CleanItem] = []
        let top = roots.flatMap(children)
        let candidates = Set(roots + top + children(H) + top.flatMap(children))
        for d in candidates where exists(d + "/Assets") && exists(d + "/ProjectSettings") && exists(d + "/Library") {
            unity.append(CleanItem(name: rel(d),
                                   detail: L("Unity Library · açılışta yeniden oluşur (ilk açılış uzun sürer)", "Unity Library · rebuilt on open (first open is slow)"),
                                   paths: [d + "/Library"]))
        }

        let keep = [".pem", ".jks", ".p12", ".keystore", ".mobileprovision"]
        let downloads = children(hp("Downloads"))
            .filter { p in !keep.contains { p.hasSuffix($0) } }
            .map { CleanItem(name: base($0), detail: "Downloads", paths: [$0]) }

        return [
            CleanSection(title: L("Paket ve araç cache'leri", "Package and tool caches"), note: L("Gerekince yeniden iner/oluşur", "Re-downloaded or rebuilt when needed"),
                         safe: true, items: caches.map { CleanItem(name: $0.0, paths: $0.1) }),
            CleanSection(title: L("Proje build çıktıları", "Project build outputs"),
                         note: L("Frontend, backend, mobil · yeniden derleyince geri gelir", "Frontend, backend, mobile · come back on the next build"),
                         safe: true, minSize: 50 << 20, items: builds),
            CleanSection(title: "Docker", note: L("Kullanılmayanlar tekrar çekilir", "Unused ones are pulled again when needed"),
                         safe: false, items: docker),
            CleanSection(title: L("iOS simülatörleri", "iOS simulators"),
                         note: L("Tamamen silinen cihaz ve içindeki uygulamalar gider", "Deleting a device removes its apps too"),
                         safe: false, minSize: 100 << 20, items: sims),
            CleanSection(title: "Android", note: L("Emülatörler ve SDK system image'ları", "Emulators and SDK system images"),
                         safe: false, items: avds + sysImages),
            CleanSection(title: "Xcode", note: L("Yayındaki sürümün arşivini sakla", "Keep the archive of your released build"), safe: false, items: xcode),
            CleanSection(title: "Claude", note: L("Ekran görüntüleri, eski konuşmalar, VM", "Screenshots, old conversations, VM"), safe: false, items: claude),
            CleanSection(title: L("Unity projeleri", "Unity projects"), note: L("Library klasörleri", "Library folders"),
                         safe: false, minSize: 200 << 20, items: unity),
            CleanSection(title: "Downloads", note: L("200 MB üstü", "Over 200 MB"), safe: false, minSize: 200 << 20, items: downloads),
        ]
    }
}

// MARK: - Cleaner

enum Cleaner {
    static func clean(_ item: CleanItem) -> String? {
        for c in item.commands { run(c) }
        var failed = 0
        for path in item.paths where exists(path) {
            guard path.hasPrefix(H + "/") else { continue }
            do { try fm.removeItem(atPath: path) } catch {
                // Some caches (e.g. Go modules) are read-only; make them writable and retry.
                run(["chmod", "-R", "u+w", path])
                do { try fm.removeItem(atPath: path) } catch { failed += 1 }
            }
        }
        return failed == 0 ? nil : "\(item.name) (\(failed) " + L("silinemedi", "could not be deleted") + ")"
    }
}

// MARK: - Store

final class Store: ObservableObject {
    @Published var sections: [CleanSection] = []
    @Published var busy = false
    @Published var status = ""
    @Published var message = ""
    @Published var free: Int64 = 0
    @Published var total: Int64 = 0

    init() { refreshDisk() }

    var selected: [CleanItem] { sections.flatMap { $0.items }.filter { $0.selected } }

    func refreshDisk() {
        let v = try? URL(fileURLWithPath: H).resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey])
        free = Int64(v?.volumeAvailableCapacity ?? 0)
        total = Int64(v?.volumeTotalCapacity ?? 0)
    }

    func scan() {
        busy = true
        message = ""
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Scanner.scan { msg in DispatchQueue.main.async { self.status = msg } }
            DispatchQueue.main.async {
                self.sections = result
                self.busy = false
                self.status = ""
                self.refreshDisk()
            }
        }
    }

    func clean(_ items: [CleanItem]) {
        busy = true
        let ids = Set(items.map { $0.id })
        let size = items.reduce(0) { $0 + $1.size }
        DispatchQueue.global(qos: .userInitiated).async {
            var errors: [String] = []
            for (i, item) in items.enumerated() {
                DispatchQueue.main.async { self.status = L("Siliniyor", "Deleting") + " (\(i + 1)/\(items.count)): \(item.name)" }
                if let e = Cleaner.clean(item) { errors.append(e) }
            }
            DispatchQueue.main.async {
                for s in self.sections.indices { self.sections[s].items.removeAll { ids.contains($0.id) } }
                self.sections.removeAll { $0.items.isEmpty }
                self.message = fmt(size) + L(" silindi.", " deleted.")
                    + (errors.isEmpty ? "" : L(" Hata: ", " Errors: ") + errors.prefix(3).joined(separator: ", "))
                self.busy = false
                self.status = ""
                self.refreshDisk()
                // APFS reports freed space with a delay.
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.refreshDisk() }
            }
        }
    }
}

// MARK: - UI

struct ContentView: View {
    @StateObject var store = Store()
    @State var pending: [CleanItem] = []
    @State var confirm = false
    @State var language = lang

    var usedRatio: Double { store.total == 0 ? 0 : Double(store.total - store.free) / Double(store.total) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.sections.isEmpty {
                Text(store.busy ? L("Taranıyor…", "Scanning…") : L("Silinecek bir şey bulunamadı", "Nothing to clean"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach($store.sections) { $section in
                        Section {
                            ForEach($section.items) { $item in row($item) }
                        } header: {
                            sectionHeader($section)
                        }
                    }
                }
            }
            Divider()
            footer
        }
        .alert(L("Kalıcı olarak silinsin mi?", "Delete permanently?"), isPresented: $confirm) {
            Button(L("Sil", "Delete"), role: .destructive) { store.clean(pending) }
            Button(L("Vazgeç", "Cancel"), role: .cancel) {}
        } message: {
            Text("\(pending.count) " + L("öğe, toplam ", "items, ") + fmt(pending.reduce(0) { $0 + $1.size })
                 + L(". Bu işlem geri alınamaz.", " in total. This cannot be undone."))
        }
        .onAppear { store.scan() }
    }

    var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: usedRatio)
                    .tint(usedRatio > 0.9 ? .red : .accentColor)
                    .frame(width: 280)
                Text(fmt(store.free) + L(" boş · ", " free · ") + fmt(store.total) + L(" toplam", " total"))
                    .font(.callout).monospacedDigit()
            }
            Spacer()
            if store.busy {
                ProgressView().controlSize(.small)
                Text(store.status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Picker("", selection: $language) {
                Text("TR").tag("tr")
                Text("EN").tag("en")
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 90)
            .disabled(store.busy)
            .onChange(of: language) { _, new in
                lang = new
                UserDefaults.standard.set(new, forKey: "lang")
                store.scan()
            }
            Button { chooseRoots() } label: { Label(L("Proje klasörleri", "Project folders"), systemImage: "folder") }
                .help(projectRoots().map(rel).joined(separator: "\n"))
                .disabled(store.busy)
            Button { store.scan() } label: { Label(L("Yeniden tara", "Rescan"), systemImage: "arrow.clockwise") }
                .disabled(store.busy)
        }
        .padding()
    }

    func chooseRoots() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: H)
        panel.message = L("Build çıktıları ve Unity projeleri için taranacak klasörleri seç",
                          "Choose the folders to search for build outputs and Unity projects")
        panel.prompt = L("Seç", "Choose")
        if panel.runModal() == .OK {
            UserDefaults.standard.set(panel.urls.map { $0.path }, forKey: "roots")
            store.scan()
        }
    }

    func sectionHeader(_ s: Binding<CleanSection>) -> some View {
        let sec = s.wrappedValue
        let all = sec.items.allSatisfy { $0.selected }
        return HStack {
            Text(sec.title).font(.headline)
            Text(sec.safe ? L("Güvenli", "Safe") : L("Kontrol et", "Review"))
                .font(.caption2.bold())
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background((sec.safe ? Color.green : Color.orange).opacity(0.25), in: Capsule())
            Text(sec.note).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(fmt(sec.total)).monospacedDigit()
            Button(all ? L("Seçimi kaldır", "Deselect all") : L("Tümünü seç", "Select all")) {
                for i in s.wrappedValue.items.indices { s.wrappedValue.items[i].selected = !all }
            }
            .buttonStyle(.link).font(.caption)
        }
    }

    func row(_ item: Binding<CleanItem>) -> some View {
        let it = item.wrappedValue
        return HStack {
            Toggle("", isOn: item.selected).labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text(it.name).lineLimit(1).truncationMode(.middle)
                if !it.detail.isEmpty {
                    Text(it.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Text(fmt(it.size)).monospacedDigit()
                .foregroundStyle(it.size > 10 << 30 ? Color.red : Color.primary)
            Button(L("Temizle", "Clean")) { ask([it]) }.disabled(store.busy)
        }
    }

    var footer: some View {
        let sel = store.selected
        return HStack {
            if !store.message.isEmpty { Text(store.message).font(.callout).lineLimit(2) }
            Spacer()
            Text(L("Seçili: ", "Selected: ") + "\(sel.count) " + L("öğe", "items") + " · " + fmt(sel.reduce(0) { $0 + $1.size }))
                .monospacedDigit()
            Button(L("Seçilenleri temizle", "Clean selected")) { ask(sel) }
                .buttonStyle(.borderedProminent).tint(.red)
                .disabled(sel.isEmpty || store.busy)
        }
        .padding()
    }

    func ask(_ items: [CleanItem]) {
        pending = items
        confirm = true
    }
}

struct DiskTemizleApp: App {
    var body: some Scene {
        WindowGroup(L("Disk Temizle", "Disk Cleaner")) {
            ContentView().frame(minWidth: 820, minHeight: 560)
        }
    }
}

// MARK: - Entry

if let i = CommandLine.arguments.firstIndex(of: "--lang"), i + 1 < CommandLine.arguments.count {
    lang = CommandLine.arguments[i + 1]
}
if CommandLine.arguments.contains("--dump") {
    for s in Scanner.scan(progress: { _ in }) {
        print("## \(s.title) — \(fmt(s.total)) · \(s.note)")
        for i in s.items { print("  \(fmt(i.size))\t\(i.name)\t\(i.detail)") }
    }
    exit(0)
}
DiskTemizleApp.main()
