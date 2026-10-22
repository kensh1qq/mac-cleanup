// Проверка поиска программ, больших файлов и подписей на этом Mac. Только читает.
// Запуск: ./test.sh
import Foundation

@main
struct Tests {
    static var fails = 0
    static func check(_ ok: Bool, _ msg: String) { if !ok { print("FAIL:", msg); fails += 1 } }

    static func main() async {
        check(describe("Xcode: DerivedData").title == "Xcode DerivedData", "подпись DerivedData")
        check(describe("Xcode: DeviceSupport").title == "Xcode DeviceSupport", "подпись DeviceSupport")
        check(describe("неизвестное").title == "неизвестное", "неизвестная метка как есть")

        let apps = await Model.findApps()
        check(!apps.isEmpty, "нашлась хоть одна программа")
        check(!apps.contains { $0.bundleID.hasPrefix("com.apple.") }, "системные Apple-программы не предлагаем")
        check(apps.allSatisfy { $0.leftovers.allSatisfy { $0.hasPrefix(lib + "/") } }, "хвосты только из ~/Library")
        check(apps.allSatisfy { $0.appKB > 0 }, "у каждой программы есть размер")
        if let tg = apps.first(where: { $0.bundleID == "ru.keepcoder.Telegram" }) {
            check(tg.leftovers.contains { $0.contains("Group Containers") }, "у Telegram найден Group Container")
        }
        print("Программы: \(apps.count)")
        for a in apps.prefix(6) {
            print("  \(human(a.totalKB).padding(toLength: 9, withPad: " ", startingAt: 0)) \(a.name) — \(ago(a.lastUsed)), хвостов \(a.leftovers.count)")
        }

        let files = await Model.findFiles()
        check(files.allSatisfy { $0.kb >= 300 * 1024 }, "все файлы ≥ 300 МБ")
        check(!files.contains { $0.path.contains(".pvm/") || $0.path.contains(".app/") }, "нет кишок пакетов")
        check(!files.contains { $0.path.hasPrefix(lib + "/") && !$0.path.contains("/MobileSync/Backup/") }, "из ~/Library только бэкапы iPhone")
        if FileManager.default.fileExists(atPath: home + "/Parallels/Windows 11.pvm") {
            check(files.contains { $0.path.hasSuffix("Windows 11.pvm") }, "виртуалка Parallels найдена")
        }
        print("Большие файлы: \(files.count)")
        for f in files.prefix(6) {
            print("  \(human(f.kb).padding(toLength: 9, withPad: " ", startingAt: 0)) \(f.name) — \(f.folder)")
        }

        print(fails == 0 ? "tests OK" : "\(fails) FAIL")
        exit(fails == 0 ? 0 : 1)
    }
}
