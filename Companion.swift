// Меню-бар, автозапуск при входе, еженедельное напоминание, проверка обновлений.
// Отдельный файл — чтобы App.swift не разрастался ещё больше.
import SwiftUI
import AppKit
import ServiceManagement
import UserNotifications

/// 1 если a > b, -1 если a < b, 0 если равны. "1.10" > "1.9" — сравнение по компонентам, не по строке.
func compareVersions(_ a: String, _ b: String) -> Int {
    let pa = a.split(separator: ".").map { Int($0) ?? 0 }
    let pb = b.split(separator: ".").map { Int($0) ?? 0 }
    for i in 0..<max(pa.count, pb.count) {
        let x = i < pa.count ? pa[i] : 0
        let y = i < pb.count ? pb[i] : 0
        if x != y { return x > y ? 1 : -1 }
    }
    return 0
}

// MARK: - Свободное место для меню-бара

@MainActor
final class DiskWatcher: ObservableObject {
    @Published var freeGB: Double = 0
    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        let v = try? URL(fileURLWithPath: home).resourceValues(forKeys: [.volumeAvailableCapacityKey])
        freeGB = Double(v?.volumeAvailableCapacity ?? 0) / 1_073_741_824
    }

    var label: String { freeGB > 0 ? String(format: "%.0f ГБ", freeGB) : "…" }
}

// MARK: - Автозапуск при входе

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Возвращает текст ошибки, если не получилось (например, приложение не в /Applications), иначе nil.
    @discardableResult
    static func setEnabled(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return "Не получилось: \(error.localizedDescription)"
        }
    }
}

// MARK: - Еженедельное напоминание

enum Reminder {
    static let id = "cc.kensh1qq.cleanup.weekly"
    private static let key = "weeklyReminder"

    static var isOn: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func set(_ on: Bool, done: @escaping (String?) -> Void = { _ in }) {
        isOn = on
        let center = UNUserNotificationCenter.current()
        guard on else {
            center.removePendingNotificationRequests(withIdentifiers: [id])
            done(nil)
            return
        }
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            guard granted else {
                Task { @MainActor in
                    isOn = false
                    done(error?.localizedDescription ?? "Уведомления запрещены в Системных настройках")
                }
                return
            }
            let content = UNMutableNotificationContent()
            content.title = "Чистка"
            content.body = "Загляни проверить, чем забит диск."
            content.sound = .default
            var date = DateComponents()
            date.weekday = 2   // понедельник
            date.hour = 11
            let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger)) { error in
                Task { @MainActor in done(error?.localizedDescription) }
            }
        }
    }
}

// MARK: - Проверка обновлений

@MainActor
final class UpdateChecker: ObservableObject {
    @Published var label = "Проверить обновления"
    private var downloadURL: String?

    func checkOrOpen() {
        if let u = downloadURL, let url = URL(string: u) { NSWorkspace.shared.open(url); return }
        Task { await check() }
    }

    func check() async {
        label = "Проверяю…"
        guard let url = URL(string: "https://api.github.com/repos/kensh1qq/mac-cleanup/releases/latest") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                label = "Не получилось проверить"
                return
            }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
            if compareVersions(latest, current) > 0 {
                downloadURL = json["html_url"] as? String
                label = "Доступна \(tag) — открыть"
            } else {
                label = "Это последняя версия"
            }
        } catch {
            label = "Нет интернета"
        }
    }
}

// MARK: - Содержимое меню-бара

struct MenuBarView: View {
    @ObservedObject var disk: DiskWatcher
    @StateObject private var updater = UpdateChecker()
    @State private var loginOn = LoginItem.isEnabled
    @State private var reminderOn = Reminder.isOn
    @State private var note: String?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("Свободно: \(String(format: "%.1f", disk.freeGB)) ГБ")
        Button("Открыть «Чистку»") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }
        Divider()
        Toggle("Запускать при входе", isOn: $loginOn)
            .onChange(of: loginOn) { _, v in
                if let err = LoginItem.setEnabled(v) { note = err; loginOn = !v }
            }
        Toggle("Напоминать раз в неделю", isOn: $reminderOn)
            .onChange(of: reminderOn) { _, v in
                Reminder.set(v) { err in if let err { note = err }; reminderOn = Reminder.isOn }
            }
        if let note { Text(note).font(.caption) }
        Divider()
        Button(updater.label) { updater.checkOrOpen() }
        Divider()
        Button("Выйти из «Чистки»") { NSApp.terminate(nil) }
    }
}
