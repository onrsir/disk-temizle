import SwiftUI
import AppKit

// MARK: - Helpers

let H = NSHomeDirectory()
let fm = FileManager.default

func hp(_ s: String) -> String { H + "/" + s }
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
        progress("Klasörler aranıyor…")
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
            progress("Boyutlar hesaplanıyor (\(d)/\(refs.count))")
        }
        for (i, (s, j)) in refs.enumerated() { sections[s].items[j].size = sizes[i] }
        for s in sections.indices {
            let min = sections[s].minSize
            sections[s].items = sections[s].items.filter { $0.size >= min }.sorted { $0.size > $1.size }
        }
        return sections.filter { !$0.items.isEmpty }
    }

    static func discover() -> [CleanSection] {
        let ip = hp("IdeaProjects")

        let caches: [(String, [String])] = [
            ("Uygulama cache'leri (~/Library/Caches)", children(hp("Library/Caches"))),
            ("Xcode DerivedData", children(hp("Library/Developer/Xcode/DerivedData"))),
            ("Gradle cache", [hp(".gradle/caches")]),
            ("npm cache", [hp(".npm/_cacache"), hp(".npm/_npx")]),
            ("pnpm store", [hp("Library/pnpm/store")]),
            ("uv (Python) cache", [hp(".cache/uv")]),
            ("Hugging Face modelleri", [hp(".cache/huggingface")]),
            ("Whisper modelleri", [hp(".cache/whisper")]),
            ("Puppeteer tarayıcıları", [hp(".cache/puppeteer")]),
        ]

        var builds: [CleanItem] = []
        let found = lines(run(["find", ip, "-maxdepth", "6",
                               "(", "-name", ".git", "-o", "-name", "Library", "-o", "-name", "build", ")", "-prune", "-o",
                               "-type", "d", "(", "-name", "node_modules", "-o", "-name", ".turbo", "-o", "-name", ".next", "-o", "-name", "Pods", ")",
                               "-prune", "-print"]))
        let labels = ["node_modules": "node_modules (paket kurulumuyla geri gelir)", ".turbo": "Turbo cache",
                      ".next": "Next.js build", "Pods": "CocoaPods (pod install ile geri gelir)"]
        for f in found { builds.append(CleanItem(name: rel(f), detail: labels[base(f)] ?? "", paths: [f])) }
        for pub in lines(run(["find", ip, "-maxdepth", "4", "-name", "pubspec.yaml", "-not", "-path", "*/node_modules/*", "-not", "-path", "*/.*"])) {
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
                    sims.append(CleanItem(name: d.name, detail: "\(os)\(booted ? " · açık" : "") · cihazı tamamen sil",
                                          paths: [dir],
                                          commands: [["xcrun", "simctl", "shutdown", d.udid], ["xcrun", "simctl", "delete", d.udid]]))
                    if !booted {
                        sims.append(CleanItem(name: d.name + " — sadece cache", detail: "\(os) · uygulamalar ve kayıtlar kalır",
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
            return CleanItem(name: (n as NSString).deletingPathExtension, detail: "Android emülatörü", paths: [avd] + own)
        }

        var xcode = children(hp("Library/Developer/Xcode/Archives")).map { d -> CleanItem in
            let apps = Set(children(d).map { base($0).components(separatedBy: " ").first ?? "" }).sorted().joined(separator: ", ")
            return CleanItem(name: "Arşiv " + base(d), detail: apps, paths: [d])
        }
        xcode += children(hp("Library/Developer/Xcode/iOS DeviceSupport")).map {
            CleanItem(name: base($0), detail: "iOS DeviceSupport (cihaz bağlanınca yeniden oluşur)", paths: [$0])
        }

        let cp = hp(".claude/projects")
        let media = lines(run(["find", cp, "-type", "f", "(", "-iname", "*.png", "-o", "-iname", "*.jpg", "-o", "-iname", "*.jpeg",
                               "-o", "-iname", "*.webp", "-o", "-iname", "*.gif", "-o", "-iname", "*.mp4", "-o", "-iname", "*.mov",
                               "-o", "-iname", "*.webm", ")"]))
        let old = lines(run(["find", cp, "-mindepth", "2", "-maxdepth", "2", "-mtime", "+30", "-not", "-name", "memory"]))
        let cl = hp("Library/Application Support/Claude")
        let claude = [
            CleanItem(name: "Ekran görüntüleri ve videolar", detail: "\(media.count) dosya · ~/.claude/projects", paths: media),
            CleanItem(name: "30 günden eski konuşmalar", detail: "\(old.count) öğe · bu konuşmalara geri dönülemez", paths: old),
            CleanItem(name: "Claude sanal makinesi (vm_bundles)", detail: "Önce Claude'u kapat · gerekince yeniden iner", paths: [cl + "/vm_bundles"]),
            CleanItem(name: "Claude uygulama cache'i", paths: [cl + "/Cache", cl + "/Code Cache", cl + "/GPUCache"]),
        ]

        var unity: [CleanItem] = []
        let candidates = Set(children(ip) + children(H) + children(ip).flatMap { children($0) })
        for d in candidates where exists(d + "/Assets") && exists(d + "/ProjectSettings") && exists(d + "/Library") {
            unity.append(CleanItem(name: rel(d), detail: "Unity Library · açılışta yeniden oluşur (ilk açılış uzun sürer)", paths: [d + "/Library"]))
        }

        let keep = [".pem", ".jks", ".p12", ".keystore", ".mobileprovision"]
        let downloads = children(hp("Downloads"))
            .filter { p in !keep.contains { p.hasSuffix($0) } }
            .map { CleanItem(name: base($0), detail: "Downloads", paths: [$0]) }

        return [
            CleanSection(title: "Cache'ler", note: "Gerekince yeniden oluşur", safe: true,
                         items: caches.map { CleanItem(name: $0.0, paths: $0.1) }),
            CleanSection(title: "Build çıktıları", note: "Yeniden derleyince geri gelir", safe: true, minSize: 50 << 20, items: builds),
            CleanSection(title: "iOS simülatörleri", note: "Tamamen silinen cihaz ve içindeki uygulamalar gider", safe: false, minSize: 100 << 20, items: sims),
            CleanSection(title: "Android emülatörleri", note: "Android Studio'dan yeniden oluşturulur", safe: false, items: avds),
            CleanSection(title: "Xcode", note: "Yayındaki sürümün arşivini sakla", safe: false, items: xcode),
            CleanSection(title: "Claude", note: "Ekran görüntüleri, eski konuşmalar, VM", safe: false, items: claude),
            CleanSection(title: "Unity projeleri", note: "Library klasörleri", safe: false, minSize: 200 << 20, items: unity),
            CleanSection(title: "Downloads", note: "200 MB üstü", safe: false, minSize: 200 << 20, items: downloads),
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
        return failed == 0 ? nil : "\(item.name) (\(failed) silinemedi)"
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
                DispatchQueue.main.async { self.status = "Siliniyor (\(i + 1)/\(items.count)): \(item.name)" }
                if let e = Cleaner.clean(item) { errors.append(e) }
            }
            DispatchQueue.main.async {
                for s in self.sections.indices { self.sections[s].items.removeAll { ids.contains($0.id) } }
                self.sections.removeAll { $0.items.isEmpty }
                self.message = "\(fmt(size)) silindi." + (errors.isEmpty ? "" : " Hata: " + errors.prefix(3).joined(separator: ", "))
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

    var usedRatio: Double { store.total == 0 ? 0 : Double(store.total - store.free) / Double(store.total) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.sections.isEmpty {
                Text(store.busy ? "Taranıyor…" : "Silinecek bir şey bulunamadı")
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
        .alert("Kalıcı olarak silinsin mi?", isPresented: $confirm) {
            Button("Sil", role: .destructive) { store.clean(pending) }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("\(pending.count) öğe, toplam \(fmt(pending.reduce(0) { $0 + $1.size })). Bu işlem geri alınamaz.")
        }
        .onAppear { store.scan() }
    }

    var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: usedRatio)
                    .tint(usedRatio > 0.9 ? .red : .accentColor)
                    .frame(width: 280)
                Text("\(fmt(store.free)) boş · \(fmt(store.total)) toplam")
                    .font(.callout).monospacedDigit()
            }
            Spacer()
            if store.busy {
                ProgressView().controlSize(.small)
                Text(store.status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Button { store.scan() } label: { Label("Yeniden tara", systemImage: "arrow.clockwise") }
                .disabled(store.busy)
        }
        .padding()
    }

    func sectionHeader(_ s: Binding<CleanSection>) -> some View {
        let sec = s.wrappedValue
        let all = sec.items.allSatisfy { $0.selected }
        return HStack {
            Text(sec.title).font(.headline)
            Text(sec.safe ? "Güvenli" : "Kontrol et")
                .font(.caption2.bold())
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background((sec.safe ? Color.green : Color.orange).opacity(0.25), in: Capsule())
            Text(sec.note).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(fmt(sec.total)).monospacedDigit()
            Button(all ? "Seçimi kaldır" : "Tümünü seç") {
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
            Button("Temizle") { ask([it]) }.disabled(store.busy)
        }
    }

    var footer: some View {
        let sel = store.selected
        return HStack {
            if !store.message.isEmpty { Text(store.message).font(.callout).lineLimit(2) }
            Spacer()
            Text("Seçili: \(sel.count) öğe · \(fmt(sel.reduce(0) { $0 + $1.size }))").monospacedDigit()
            Button("Seçilenleri temizle") { ask(sel) }
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
        WindowGroup("Disk Temizle") {
            ContentView().frame(minWidth: 780, minHeight: 560)
        }
    }
}

// MARK: - Entry

if CommandLine.arguments.contains("--dump") {
    for s in Scanner.scan(progress: { _ in }) {
        print("## \(s.title) — \(fmt(s.total))")
        for i in s.items.prefix(6) { print("  \(fmt(i.size))\t\(i.name)\t\(i.detail)") }
    }
    exit(0)
}
DiskTemizleApp.main()
