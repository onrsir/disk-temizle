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
            let size = diskSize(snapshot[s].items[j].paths)
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

        let caches: [(String, [String])] = [
            (L("Uygulama cache'leri", "App caches") + " (~/Library/Caches)", children(hp("Library/Caches"))),
            ("Xcode DerivedData", children(hp("Library/Developer/Xcode/DerivedData"))),
            ("Gradle cache", [hp(".gradle/caches")]),
            ("npm cache", [hp(".npm/_cacache"), hp(".npm/_npx")]),
            ("pnpm store", [hp("Library/pnpm/store")]),
            ("uv (Python) cache", [hp(".cache/uv")]),
            (L("Hugging Face modelleri", "Hugging Face models"), [hp(".cache/huggingface")]),
            (L("Whisper modelleri", "Whisper models"), [hp(".cache/whisper")]),
            (L("Puppeteer tarayıcıları", "Puppeteer browsers"), [hp(".cache/puppeteer")]),
        ]

        var builds: [CleanItem] = []
        // find with no start path would search the current directory.
        let found = roots.isEmpty ? [] : lines(run(["find"] + roots + ["-maxdepth", "6",
                               "(", "-name", ".git", "-o", "-name", "Library", "-o", "-name", "build", ")", "-prune", "-o",
                               "-type", "d", "(", "-name", "node_modules", "-o", "-name", ".turbo", "-o", "-name", ".next", "-o", "-name", "Pods", ")",
                               "-prune", "-print"]))
        let labels = ["node_modules": L("node_modules (paket kurulumuyla geri gelir)", "node_modules (restored by package install)"),
                      ".turbo": "Turbo cache",
                      ".next": "Next.js build",
                      "Pods": L("CocoaPods (pod install ile geri gelir)", "CocoaPods (restored by pod install)")]
        for f in found { builds.append(CleanItem(name: rel(f), detail: labels[base(f)] ?? "", paths: [f])) }
        let pubspecs = roots.isEmpty ? [] : lines(run(["find"] + roots + ["-maxdepth", "4", "-name", "pubspec.yaml",
                                                                          "-not", "-path", "*/node_modules/*", "-not", "-path", "*/.*"]))
        for pub in pubspecs {
            let b = (pub as NSString).deletingLastPathComponent + "/build"
            if exists(b) { builds.append(CleanItem(name: rel(b), detail: "Flutter build", paths: [b])) }
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
            CleanSection(title: L("Cache'ler", "Caches"), note: L("Gerekince yeniden oluşur", "Rebuilt when needed"), safe: true,
                         items: caches.map { CleanItem(name: $0.0, paths: $0.1) }),
            CleanSection(title: L("Build çıktıları", "Build outputs"), note: L("Yeniden derleyince geri gelir", "Come back on the next build"),
                         safe: true, minSize: 50 << 20, items: builds),
            CleanSection(title: L("iOS simülatörleri", "iOS simulators"),
                         note: L("Tamamen silinen cihaz ve içindeki uygulamalar gider", "Deleting a device removes its apps too"),
                         safe: false, minSize: 100 << 20, items: sims),
            CleanSection(title: L("Android emülatörleri", "Android emulators"), note: L("Android Studio'dan yeniden oluşturulur", "Recreate them in Android Studio"),
                         safe: false, items: avds),
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
            do { try fm.removeItem(atPath: path) } catch { failed += 1 }
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
        for i in s.items.prefix(3) { print("  \(fmt(i.size))\t\(i.name)\t\(i.detail)") }
    }
    exit(0)
}
DiskTemizleApp.main()
