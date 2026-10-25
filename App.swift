// «Чистка» — нативное окно поверх скрипта cleanup (лежит в Contents/Resources).
// Мусор, программы и большие файлы уходят в Корзину. Насовсем удаляет только «Очистить Корзину».
import SwiftUI
import AppKit
import CoreServices

let accent = Color(red: 0.85, green: 0.47, blue: 0.34)
let home = NSHomeDirectory()
let lib = home + "/Library"

func human(_ kb: Int64) -> String {
    kb >= 1_048_576 ? String(format: "%.1f ГБ", Double(kb) / 1_048_576) : "\(kb / 1024) МБ"
}

func ago(_ d: Date?) -> String {
    guard let d else { return "не открывалось" }
    let days = Int(-d.timeIntervalSinceNow / 86400)
    switch days {
    case ..<1: return "открывалось сегодня"
    case 1: return "открывалось вчера"
    case ..<30: return "открывалось \(days) дн. назад"
    case ..<365: return "открывалось \(days / 30) мес. назад"
    default: return "не открывалось больше года"
    }
}

/// Короткая форма для строк, где дата склеивается с другим текстом через «·» —
/// длинное предложение там обрезается посередине и превращается в кашу.
func agoShort(_ d: Date?) -> String {
    guard let d else { return "не открывалось" }
    let days = Int(-d.timeIntervalSinceNow / 86400)
    switch days {
    case ..<1: return "сегодня"
    case 1: return "вчера"
    case ..<30: return "\(days) дн. назад"
    case ..<365: return "\(days / 30) мес. назад"
    default: return "больше года назад"
    }
}

// MARK: - Шелл

enum Sh {
    @discardableResult
    static func run(_ exe: String, _ args: [String]) -> (out: String, ok: Bool) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return ("", false) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (String(decoding: data, as: UTF8.self), p.terminationStatus == 0)
    }

    static func duKB(_ paths: [String]) -> Int64 {
        guard !paths.isEmpty else { return 0 }
        return run("/usr/bin/du", ["-sk"] + paths).out.split(separator: "\n")
            .reduce(0) { $0 + (Int64($1.split(separator: "\t").first ?? "") ?? 0) }
    }

    static func lastUsed(_ path: String) -> Date? {
        guard let item = MDItemCreate(nil, path as CFString) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }
}

// MARK: - Данные

struct Junk: Identifiable {
    let id: Int          // номер для `cleanup trash`
    let kb: Int64
    let title: String
    let note: String
    let bundleID: String?
    let symbol: String
    let running: Bool
}

/// Подписи и иконки к целям скрипта. Чего нет в словаре — покажется как есть.
func describe(_ label: String) -> (title: String, note: String, bundle: String?, symbol: String) {
    let map: [(String, String, String, String?, String)] = [
        ("Cursor",   "Cursor",              "Откаты правок AI-агента",                           "com.todesktop.230313mzl4w4u92", "cursorarrow"),
        ("Telegram", "Telegram",            "Кэш фото и видео — подгрузится заново",             "ru.keepcoder.Telegram",         "paperplane"),
        ("Spotify",  "Spotify",             "Кэш треков",                                        "com.spotify.client",            "music.note"),
        ("Chrome",   "Google Chrome",       "Кэш страниц. Логины и вкладки не трогаем",          "com.google.Chrome",             "globe"),
        ("Codex",    "Codex",               "Кэш и скачанные рантаймы",                          "com.openai.codex",              "terminal"),
        ("Android",  "Android-эмуляторы",   "Образы и устройства — создашь заново в Studio",     "com.google.android.studio",     "iphone.gen3"),
        ("Gradle",   "Gradle",              "Скачанные зависимости сборок",                      nil,                             "shippingbox"),
        ("Xcode: Der","Xcode DerivedData",   "Промежуточные файлы сборок",                        "com.apple.dt.Xcode",            "hammer"),
        ("Xcode: Dev","Xcode DeviceSupport", "Файлы под подключавшиеся iPhone — скачаются снова", "com.apple.dt.Xcode",            "iphone"),
        ("iOS",      "iOS-симуляторы",      "Данные внутри. Сами устройства останутся",          "com.apple.iphonesimulator",     "ipad.and.iphone"),
        ("npm",      "npm",                 "Кэш пакетов",                                       nil,                             "cube.box"),
        ("Homebrew", "Homebrew",            "Скачанные установщики пакетов",                     nil,                             "mug"),
        ("pip",      "pip / uv",            "Кэш Python-пакетов",                                nil,                             "chevron.left.forwardslash.chevron.right"),
        ("Yarn",     "Yarn / pnpm",         "Кэш JS-пакетов",                                    nil,                             "cube"),
        ("Discord",  "Discord",             "Кэш картинок и видео",                              "com.hnc.Discord",               "bubble.left.and.bubble.right"),
        ("Сборки",   "Сборки проектов",     ".next, Rust target, android build — пересоберутся", nil,                             "square.stack.3d.up"),
    ]
    // длинные ключи первыми, чтобы «Xcode: De…» не съел «Xcode: D…»
    for (key, title, note, bundle, symbol) in map.sorted(by: { $0.0.count > $1.0.count }) where label.hasPrefix(key) {
        return (title, note, bundle, symbol)
    }
    return (label, "", nil, "folder")
}

struct AppEntry: Identifiable {
    var id: String { path }
    let path: String
    let name: String
    let bundleID: String
    let appKB: Int64
    let leftovers: [String]   // хвосты в ~/Library
    let leftKB: Int64
    let lastUsed: Date?
    var totalKB: Int64 { appKB + leftKB }
    var stale: Bool { lastUsed.map { -$0.timeIntervalSinceNow > 60 * 86400 } ?? true }
}

struct BigFile: Identifiable {
    var id: String { path }
    let path: String
    let kb: Int64
    let lastUsed: Date?
    var name: String { (path as NSString).lastPathComponent }
    var folder: String { (path as NSString).deletingLastPathComponent.replacingOccurrences(of: home, with: "~") }
    var note: String {
        let ext = (path as NSString).pathExtension.lowercased()
        if path.contains("/MobileSync/Backup/") { return "Резервная копия iPhone" }
        switch ext {
        case "pvm", "utm", "vmwarevm": return "Виртуальная машина"
        case "dmg", "iso", "pkg": return "Установщик / образ — после установки не нужен"
        case "zip", "rar", "7z", "gz", "tar": return "Архив"
        case "mov", "mp4", "mkv", "avi": return "Видео"
        default: return ""
        }
    }
}

enum Tab: String, CaseIterable, Identifiable {
    case junk = "Мусор", apps = "Программы", files = "Большие файлы"
    var id: String { rawValue }
}

enum JunkPhase { case scanning, ready, cleaning, done(freed: Int64) }

struct Pending {
    let title: String, message: String, button: String
    let action: () -> Void
}

// MARK: - Модель

@MainActor
final class Model: ObservableObject {
    @Published var tab: Tab = .junk
    @Published var totalBytes: Int64 = 0
    @Published var freeBytes: Int64 = 0
    @Published var toast: String?

    @Published var junkPhase: JunkPhase = .scanning
    @Published var junk: [Junk] = []
    @Published var selected: Set<Int> = []

    @Published var apps: [AppEntry]?
    @Published var files: [BigFile]?
    @Published var busy: Set<String> = []   // пути, которые сейчас уходят в Корзину
    @Published var emptying = false

    private let tool = Bundle.main.path(forResource: "cleanup", ofType: nil) ?? "cleanup"

    var selectedKB: Int64 { junk.filter { selected.contains($0.id) && !$0.running }.reduce(0) { $0 + $1.kb } }

    /// Сколько подсветить на полосе диска.
    var pickedKB: Int64 {
        guard tab == .junk, case .ready = junkPhase else { return 0 }
        return selectedKB
    }

    func refreshDisk() {
        let v = try? URL(fileURLWithPath: home)
            .resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
        totalBytes = Int64(v?.volumeTotalCapacity ?? 0)
        freeBytes = Int64(v?.volumeAvailableCapacity ?? 0)
    }

    func show(_ text: String) {
        withAnimation(.spring(duration: 0.4)) { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(5))
            if toast == text { withAnimation { toast = nil } }
        }
    }

    func rescan() {
        switch tab {
        case .junk: scanJunk()
        case .apps: apps = nil; scanApps()
        case .files: files = nil; scanFiles()
        }
    }

    func open(_ t: Tab) {
        withAnimation(.spring(duration: 0.3)) { tab = t }
        if t == .apps, apps == nil { scanApps() }
        if t == .files, files == nil { scanFiles() }
    }

    // Мусор

    func scanJunk() {
        withAnimation(.easeInOut(duration: 0.25)) { junkPhase = .scanning }
        refreshDisk()
        let tool = tool
        Task.detached {
            let parsed: [Junk] = Sh.run("/bin/bash", [tool, "list"]).out.split(separator: "\n").compactMap { line in
                let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard f.count >= 5, let id = Int(f[0]), let kb = Int64(f[1]) else { return nil }
                let d = describe(f[3])
                return Junk(id: id, kb: kb, title: d.title, note: d.note, bundleID: d.bundle, symbol: d.symbol, running: f[4] == "1")
            }.sorted { $0.kb > $1.kb }
            await MainActor.run {
                self.junk = parsed
                self.selected = Set(parsed.filter { !$0.running }.map(\.id))
                withAnimation(.spring(duration: 0.45)) { self.junkPhase = .ready }
            }
        }
    }

    func cleanJunk() {
        let ids = junk.filter { selected.contains($0.id) && !$0.running }.map { String($0.id) }
        guard !ids.isEmpty else { return }
        let freed = selectedKB
        withAnimation { junkPhase = .cleaning }
        let tool = tool
        Task.detached {
            Sh.run("/bin/bash", [tool, "trash"] + ids)
            await MainActor.run {
                self.refreshDisk()
                withAnimation(.spring(duration: 0.5, bounce: 0.3)) { self.junkPhase = .done(freed: freed) }
            }
        }
    }

    func toggle(_ id: Int) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    /// Закрыть приложение по-хорошему (как ⌘Q).
    func quit(bundleID: String, then: @escaping () -> Void) {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        running.forEach { $0.terminate() }
        Task {
            if !running.isEmpty { try? await Task.sleep(for: .seconds(2)) }
            then()
        }
    }

    // Корзина

    func emptyTrash() {
        let before = freeBytes
        emptying = true
        Task.detached {
            let ok = Sh.run("/usr/bin/osascript", ["-e", "tell application \"Finder\" to empty trash"]).ok
            try? await Task.sleep(for: .seconds(1.5))   // APFS отдаёт место не сразу
            await MainActor.run {
                self.emptying = false
                self.refreshDisk()
                if ok {
                    let freed = max(0, self.freeBytes - before) / 1024
                    self.show(freed > 0 ? "Корзина очищена · освобождено \(human(freed))" : "Корзина очищена")
                    if case .done = self.junkPhase { self.scanJunk() }
                } else {
                    self.show("Нет доступа к Finder: Настройки → Конфиденциальность → Автоматизация → Чистка")
                }
            }
        }
    }

    // Программы

    func scanApps() {
        Task.detached {
            let found = await Model.findApps()
            await MainActor.run { withAnimation(.spring(duration: 0.45)) { self.apps = found } }
        }
    }

    nonisolated static func findApps() async -> [AppEntry] {
        let fm = FileManager.default
        var paths: [String] = []
        for dir in ["/Applications", home + "/Applications"] {
            for n in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where n.hasSuffix(".app") {
                paths.append(dir + "/" + n)
            }
        }
        let groups = (try? fm.contentsOfDirectory(atPath: lib + "/Group Containers")) ?? []
        return await withTaskGroup(of: AppEntry?.self) { g in
            for p in paths { g.addTask { Model.appEntry(p, groups) } }
            var out: [AppEntry] = []
            for await e in g { if let e { out.append(e) } }
            return out.sorted { $0.totalKB > $1.totalKB }
        }
    }

    nonisolated static func appEntry(_ path: String, _ groups: [String]) -> AppEntry? {
        // ярлык (симлинк) место не занимает — не предлагаем
        guard (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) == nil,
              let bid = Bundle(path: path)?.bundleIdentifier,
              !bid.hasPrefix("com.apple."), bid != "cc.kensh1qq.cleanup" else { return nil }
        let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        var cands = ["Application Support/\(name)", "Application Support/\(bid)", "Caches/\(bid)", "Caches/\(name)",
                     "Containers/\(bid)", "Preferences/\(bid).plist", "Saved Application State/\(bid).savedState",
                     "Logs/\(name)", "HTTPStorages/\(bid)", "WebKit/\(bid)"].map { lib + "/" + $0 }
        cands += groups.filter { $0 == bid || $0.hasSuffix("." + bid) }.map { lib + "/Group Containers/" + $0 }
        let left = Array(Set(cands.filter { FileManager.default.fileExists(atPath: $0) })).sorted()
        // Spotlight дату запуска хранит не всегда — добираем: открыта сейчас / когда менялись её данные
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bid).isEmpty ? nil : Date()
        let touched = left.compactMap { try? FileManager.default.attributesOfItem(atPath: $0)[.modificationDate] as? Date }
        let used = ([Sh.lastUsed(path), running].compactMap { $0 } + touched).max()
        return AppEntry(path: path, name: name, bundleID: bid, appKB: Sh.duKB([path]),
                        leftovers: left, leftKB: Sh.duKB(left), lastUsed: used)
    }

    func uninstall(_ a: AppEntry) {
        busy.insert(a.path)
        quit(bundleID: a.bundleID) {
            self.recycle([a.path] + a.leftovers) { ok in
                self.busy.remove(a.path)
                if ok {
                    withAnimation(.spring(duration: 0.4)) { self.apps?.removeAll { $0.path == a.path } }
                    self.show("\(a.name) в Корзине · \(human(a.totalKB))")
                } else {
                    self.show("Не получилось удалить \(a.name)")
                }
            }
        }
    }

    // Большие файлы

    func scanFiles() {
        Task.detached {
            let found = await Model.findFiles()
            await MainActor.run { withAnimation(.spring(duration: 0.45)) { self.files = found } }
        }
    }

    nonisolated static func findFiles() async -> [BigFile] {
        let fm = FileManager.default
        var paths = Set<String>()
        for raw in Sh.run("/usr/bin/mdfind", ["-onlyin", home, "kMDItemFSSize > 524288000"]).out.split(separator: "\n") {
            var p = String(raw)
            if p.hasPrefix(lib + "/") || p.hasPrefix(home + "/.") || p.contains(".app/") || p.hasSuffix(".app") { continue }
            // файл внутри пакета (виртуалка, медиатека) — показываем пакет целиком, а не его кишки
            for ext in [".pvm", ".utm", ".vmwarevm", ".photoslibrary"] {
                if let r = p.range(of: ext + "/") { p = String(p[..<r.lowerBound]) + ext }
            }
            paths.insert(p)
        }
        // Spotlight их часто не видит
        for n in (try? fm.contentsOfDirectory(atPath: home + "/Parallels")) ?? [] where n.hasSuffix(".pvm") {
            paths.insert(home + "/Parallels/" + n)
        }
        let backups = lib + "/Application Support/MobileSync/Backup"
        for n in (try? fm.contentsOfDirectory(atPath: backups)) ?? [] { paths.insert(backups + "/" + n) }

        return await withTaskGroup(of: BigFile.self) { g in
            for p in paths { g.addTask { BigFile(path: p, kb: Sh.duKB([p]), lastUsed: Sh.lastUsed(p)) } }
            var out: [BigFile] = []
            for await f in g where f.kb >= 300 * 1024 { out.append(f) }
            return Array(out.sorted { $0.kb > $1.kb }.prefix(50))
        }
    }

    func trashFile(_ f: BigFile) {
        busy.insert(f.path)
        recycle([f.path]) { ok in
            self.busy.remove(f.path)
            if ok {
                withAnimation(.spring(duration: 0.4)) { self.files?.removeAll { $0.path == f.path } }
                self.show("\(f.name) в Корзине · \(human(f.kb))")
            } else {
                self.show("Не получилось переместить \(f.name)")
            }
        }
    }

    private func recycle(_ paths: [String], done: @escaping (Bool) -> Void) {
        NSWorkspace.shared.recycle(paths.map { URL(fileURLWithPath: $0) }) { _, err in
            Task { @MainActor in self.refreshDisk(); done(err == nil) }
        }
    }
}

// MARK: - Мелкие вьюхи

struct Glass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .underWindowBackground
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

struct Icon: View {
    var path: String? = nil
    var bundleID: String? = nil
    var symbol = "folder"
    var body: some View {
        if let p = path ?? bundleID.flatMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)?.path }) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: p)).resizable().frame(width: 34, height: 34)
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.primary.opacity(0.07))
                .frame(width: 30, height: 30)
                .overlay(Image(systemName: symbol).font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary))
                .frame(width: 34, height: 34)
        }
    }
}

struct DiskBar: View {
    let total: Int64, free: Int64, picked: Int64   // байты
    var body: some View {
        let used = max(total - free, 0)
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { g in
                let w = g.size.width, t = Double(max(total, 1))
                let usedW = w * Double(used) / t
                let pickW = min(w * Double(picked) / t, usedW)
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.07))
                    Capsule().fill(.primary.opacity(0.28)).frame(width: usedW)
                    Rectangle()
                        .fill(LinearGradient(colors: [accent.opacity(0.85), accent], startPoint: .leading, endPoint: .trailing))
                        .frame(width: pickW).offset(x: usedW - pickW)
                }
                .clipShape(Capsule())
                .animation(.spring(duration: 0.4), value: picked)
                .animation(.spring(duration: 0.6), value: free)
            }
            .frame(height: 8)
            HStack(spacing: 16) {
                legend(.primary.opacity(0.28), "Занято", human(used / 1024))
                if picked > 0 { legend(accent, "К очистке", human(picked / 1024)).transition(.opacity) }
                legend(.primary.opacity(0.1), "Свободно", human(free / 1024))
                Spacer()
            }
        }
    }
    func legend(_ c: Color, _ t: String, _ v: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(c).frame(width: 7, height: 7)
            Text(t).foregroundStyle(.secondary)
            Text(v).monospacedDigit().contentTransition(.numericText())
        }
        .font(.system(size: 11.5))
    }
}

struct Tabs: View {
    @ObservedObject var m: Model
    @Namespace private var ns
    var body: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases) { t in
                Text(t.rawValue)
                    .font(.system(size: 12.5, weight: .medium))
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .foregroundStyle(m.tab == t ? .primary : .secondary)
                    .background {
                        if m.tab == t {
                            Capsule().fill(.primary.opacity(0.1)).matchedGeometryEffect(id: "pill", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                    .onTapGesture { m.open(t) }
            }
        }
        .padding(3)
        .background(Capsule().fill(.primary.opacity(0.05)))
    }
}

struct Check: View {
    let on: Bool
    var body: some View {
        ZStack {
            Circle().strokeBorder(on ? accent : .primary.opacity(0.25), lineWidth: 1.5)
            Circle().fill(accent).padding(on ? 0 : 9).opacity(on ? 1 : 0)
            Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                .scaleEffect(on ? 1 : 0.3).opacity(on ? 1 : 0)
        }
        .frame(width: 18, height: 18)
        .animation(.spring(duration: 0.3, bounce: 0.4), value: on)
    }
}

struct Pill: View {
    let text: String
    var color: Color = .orange
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }
}

struct SizeBar: View {
    let kb: Int64, maxKB: Int64
    var lit = true
    var body: some View {
        Capsule().fill(.primary.opacity(0.08)).frame(width: 56, height: 3)
            .overlay(alignment: .leading) {
                Capsule().fill(lit ? accent : .primary.opacity(0.3))
                    .frame(width: max(3, 56 * CGFloat(kb) / CGFloat(max(maxKB, 1))))
            }
    }
}

struct Chip: ButtonStyle {
    var destructive = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(destructive ? accent : .primary)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill((destructive ? accent : .primary).opacity(configuration.isPressed ? 0.2 : 0.09)))
    }
}

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18).padding(.vertical, 9)
            .background(Capsule().fill(accent))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(Capsule().fill(.primary.opacity(configuration.isPressed ? 0.12 : 0.07)))
    }
}

/// Строка списка: всё, что одинаково у мусора, программ и файлов.
struct RowShell<Lead: View, Trail: View>: View {
    let title: String
    let subtitle: String
    var pill: (String, Color)? = nil
    var dim = false
    @ViewBuilder let lead: () -> Lead
    @ViewBuilder let trail: (_ hover: Bool) -> Trail
    @State private var hover = false

    var body: some View {
        HStack(spacing: 12) {
            lead()
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    if let pill { Pill(text: pill.0, color: pill.1) }
                }
                Text(subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            trail(hover)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.primary.opacity(hover ? 0.05 : 0)))
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        .opacity(dim ? 0.75 : 1)
    }
}

struct Size: View {
    let kb: Int64, maxKB: Int64
    var lit = true
    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            Text(human(kb)).font(.system(size: 13, weight: .semibold)).monospacedDigit()
            SizeBar(kb: kb, maxKB: maxKB, lit: lit)
        }
        .frame(width: 72, alignment: .trailing)
    }
}

struct Skeleton: View {
    @State private var pulse = false
    var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<7, id: \.self) { _ in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 8).frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 3).frame(width: 130, height: 10)
                        RoundedRectangle(cornerRadius: 3).frame(width: 220, height: 8)
                    }
                    Spacer()
                    RoundedRectangle(cornerRadius: 3).frame(width: 50, height: 10)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
            }
        }
        .foregroundStyle(.primary.opacity(pulse ? 0.09 : 0.04))
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever()) { pulse = true } }
    }
}

// MARK: - Экран

struct ContentView: View {
    @StateObject private var m = Model()
    @State private var pending: Pending?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            Group {
                switch m.tab {
                case .junk: junkTab
                case .apps: appsTab
                case .files: filesTab
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(width: 640, height: 740)
        .background(Glass().ignoresSafeArea())
        .overlay(alignment: .bottom) { toast }
        .alert(pending?.title ?? "", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button("Отмена", role: .cancel) {}
            Button(pending?.button ?? "OK", role: .destructive) { pending?.action() }
        } message: {
            Text(pending?.message ?? "")
        }
        .onAppear { m.scanJunk() }
    }

    func askEmptyTrash() {
        pending = Pending(title: "Очистить Корзину?",
                          message: "Всё, что в ней лежит, удалится насовсем. Отменить будет нельзя.",
                          button: "Очистить", action: m.emptyTrash)
    }

    // Шапка

    var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Чистка").font(.system(size: 24, weight: .semibold))
                    Text(subtitle).font(.system(size: 12.5)).foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                Spacer()
                HStack(spacing: 8) {
                    round(m.emptying ? nil : "trash", help: "Очистить Корзину", action: askEmptyTrash)
                        .disabled(m.emptying)
                    round("arrow.clockwise", help: "Пересканировать", action: m.rescan)
                }
            }
            DiskBar(total: m.totalBytes, free: m.freeBytes, picked: m.pickedKB * 1024)
            Tabs(m: m)
        }
        .padding(.horizontal, 28).padding(.top, 34).padding(.bottom, 16)
    }

    func round(_ symbol: String?, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let symbol { Image(systemName: symbol).font(.system(size: 12, weight: .semibold)) }
                else { ProgressView().controlSize(.small) }
            }
            .frame(width: 28, height: 28)
            .background(Circle().fill(.primary.opacity(0.07)))
        }
        .buttonStyle(.plain).help(help)
    }

    var subtitle: String {
        switch m.tab {
        case .junk:
            switch m.junkPhase {
            case .scanning: return "Ищу, что можно убрать…"
            case .cleaning: return "Переношу в Корзину…"
            case .done: return "Готово"
            case .ready:
                let all = m.junk.reduce(Int64(0)) { $0 + $1.kb }
                return m.junk.isEmpty ? "Мусора не нашлось" : "Нашлось \(human(all)) в \(m.junk.count) местах"
            }
        case .apps:
            guard let a = m.apps else { return "Считаю программы и их данные…" }
            return "\(a.count) программ · \(human(a.reduce(0) { $0 + $1.totalKB }))"
        case .files:
            guard let f = m.files else { return "Ищу файлы больше 500 МБ…" }
            return f.isEmpty ? "Больших файлов не нашлось" : "\(f.count) больших · \(human(f.reduce(0) { $0 + $1.kb }))"
        }
    }

    // Мусор

    @ViewBuilder var junkTab: some View {
        switch m.junkPhase {
        case .scanning: Skeleton().transition(.opacity)
        case .ready, .cleaning: junkList.transition(.opacity)
        case .done(let freed): junkDone(freed).transition(.scale(scale: 0.96).combined(with: .opacity))
        }
    }

    var cleaning: Bool { if case .cleaning = m.junkPhase { return true }; return false }

    var junkList: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 2) {
                    let maxKB = m.junk.map(\.kb).max() ?? 1
                    ForEach(m.junk) { j in
                        let on = m.selected.contains(j.id) && !j.running
                        RowShell(title: j.title, subtitle: j.note, pill: j.running ? ("Открыто", .orange) : nil, dim: j.running) {
                            HStack(spacing: 12) {
                                Check(on: on).opacity(j.running ? 0.35 : 1)
                                Icon(bundleID: j.bundleID, symbol: j.symbol).saturation(j.running ? 0.3 : 1)
                            }
                        } trail: { _ in
                            if j.running, let b = j.bundleID {
                                Button("Закрыть") { m.quit(bundleID: b) { m.scanJunk() } }.buttonStyle(Chip())
                            }
                            Size(kb: j.kb, maxKB: maxKB, lit: on)
                        }
                        .onTapGesture { if !j.running { m.toggle(j.id) } }
                    }
                }
                .padding(12)
            }
            .disabled(cleaning)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Всё уходит в Корзину").font(.system(size: 12, weight: .medium))
                    Text("Передумал — достань обратно").font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: m.cleanJunk) {
                    HStack(spacing: 8) {
                        if cleaning { ProgressView().controlSize(.small).tint(.white) }
                        Text(cleaning ? "Чищу…" : "Очистить \(human(m.selectedKB))")
                            .monospacedDigit().contentTransition(.numericText())
                    }
                }
                .buttonStyle(PrimaryButton())
                .disabled(m.selectedKB == 0 || cleaning)
                .opacity(m.selectedKB == 0 ? 0.4 : 1)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 28).padding(.vertical, 16)
            .background(.bar)
            .overlay(alignment: .top) { Divider().opacity(0.5) }
        }
    }

    func junkDone(_ freed: Int64) -> some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                Circle().fill(accent.opacity(0.12)).frame(width: 96, height: 96)
                Image(systemName: "checkmark").font(.system(size: 36, weight: .semibold)).foregroundStyle(accent)
            }
            VStack(spacing: 6) {
                Text("\(human(freed)) в Корзине").font(.system(size: 22, weight: .semibold))
                Text("Очисти Корзину, чтобы место вернулось на диск.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button("Готово", action: m.scanJunk).buttonStyle(SecondaryButton())
                Button(action: askEmptyTrash) {
                    HStack(spacing: 8) {
                        if m.emptying { ProgressView().controlSize(.small).tint(.white) }
                        Text(m.emptying ? "Очищаю…" : "Очистить Корзину")
                    }
                }
                .buttonStyle(PrimaryButton()).disabled(m.emptying)
            }
            .padding(.top, 6)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // Программы

    @ViewBuilder var appsTab: some View {
        if let apps = m.apps {
            ScrollView {
                VStack(spacing: 2) {
                    let stale = apps.filter(\.stale)
                    if !stale.isEmpty {
                        banner("clock.arrow.circlepath",
                               "Давно не открывались: \(stale.count) · \(human(stale.reduce(0) { $0 + $1.totalKB }))",
                               "Больше двух месяцев. Скорее всего, не нужны.")
                    }
                    let maxKB = apps.map(\.totalKB).max() ?? 1
                    ForEach(apps) { a in
                        let extra = a.leftKB > 0 ? " · данные \(human(a.leftKB))" : ""
                        RowShell(title: a.name, subtitle: ago(a.lastUsed).capitalizedFirst + extra,
                                 pill: a.stale ? ("Давно не открывалось", .secondary) : nil) {
                            Icon(path: a.path)
                        } trail: { hover in
                            if m.busy.contains(a.path) {
                                ProgressView().controlSize(.small)
                            } else {
                                Button("Удалить") { askUninstall(a) }.buttonStyle(Chip(destructive: true))
                                    .opacity(hover ? 1 : 0)
                            }
                            Size(kb: a.totalKB, maxKB: maxKB, lit: a.stale)
                        }
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                }
                .padding(12)
            }
        } else {
            Skeleton()
        }
    }

    func askUninstall(_ a: AppEntry) {
        let tail = a.leftovers.isEmpty ? "" :
            "\n\nВместе с данными (\(human(a.leftKB))):\n" + a.leftovers.map { $0.replacingOccurrences(of: home, with: "~") }.joined(separator: "\n")
        pending = Pending(title: "Удалить \(a.name)?",
                          message: "Программа уйдёт в Корзину — \(human(a.totalKB)). Если открыта, сначала закроется." + tail,
                          button: "В Корзину") { m.uninstall(a) }
    }

    // Большие файлы

    @ViewBuilder var filesTab: some View {
        if let files = m.files {
            if files.isEmpty {
                empty("doc.badge.checkmark", "Файлов больше 500 МБ нет")
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        let maxKB = files.map(\.kb).max() ?? 1
                        ForEach(files) { f in
                            let sub = [f.note.isEmpty ? nil : f.note, f.folder, agoShort(f.lastUsed)].compactMap { $0 }.joined(separator: " · ")
                            RowShell(title: f.name, subtitle: sub) {
                                Icon(path: f.path)
                            } trail: { hover in
                                if m.busy.contains(f.path) {
                                    ProgressView().controlSize(.small)
                                } else {
                                    HStack(spacing: 6) {
                                        Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: f.path)]) }
                                            label: { Image(systemName: "magnifyingglass") }
                                            .buttonStyle(Chip()).help("Показать в Finder")
                                        Button("В Корзину") { askTrash(f) }.buttonStyle(Chip(destructive: true))
                                    }
                                    .opacity(hover ? 1 : 0)
                                }
                                Size(kb: f.kb, maxKB: maxKB)
                            }
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                        }
                    }
                    .padding(12)
                }
            }
        } else {
            Skeleton()
        }
    }

    func askTrash(_ f: BigFile) {
        pending = Pending(title: "Переместить в Корзину?",
                          message: "\(f.name) — \(human(f.kb))\n\(f.folder)",
                          button: "В Корзину") { m.trashFile(f) }
    }

    // Общее

    func banner(_ symbol: String, _ title: String, _ sub: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(accent)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(accent.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(sub).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(accent.opacity(0.06)))
        .padding(.bottom, 8)
    }

    func empty(_ symbol: String, _ text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 32)).foregroundStyle(.tertiary)
            Text(text).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder var toast: some View {
        if let t = m.toast {
            Text(t)
                .font(.system(size: 12.5, weight: .medium))
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.primary.opacity(0.08)))
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                .padding(.bottom, 90)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

#if !TEST
@main
struct ChistkaApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
            .windowStyle(.hiddenTitleBar)
            .windowResizability(.contentSize)
    }
}
#endif
