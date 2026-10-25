// Проверка поиска программ, больших файлов и подписей на этом Mac. Только читает —
// ничего не удаляет, не регистрирует автозапуск, не запрашивает разрешение на уведомления.
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

        check(compareVersions("1.2", "1.1") == 1, "1.2 > 1.1")
        check(compareVersions("1.10", "1.9") == 1, "1.10 > 1.9 — по компонентам, не по строке")
        check(compareVersions("1.2", "1.2") == 0, "1.2 == 1.2")
        check(compareVersions("1.1", "1.2") == -1, "1.1 < 1.2")

        let colimaNote = BigFile(path: home + "/.colima", kb: 1024, lastUsed: nil).note
        check(colimaNote.contains("образ") && colimaNote.contains("контейнер"), "подпись .colima")
        check(BigFile(path: home + "/Downloads/design.psd", kb: 1024, lastUsed: nil).note == "Давно лежит в Downloads", "подпись старого файла в Downloads")
        check(BigFile(path: home + "/Desktop/old.psd", kb: 1024, lastUsed: nil).note == "Давно лежит на Рабочем столе", "подпись старого файла на Рабочем столе")
        check(BigFile(path: home + "/Downloads/app.dmg", kb: 1024, lastUsed: nil).note.contains("Установщик"), "расширение важнее папки — .dmg не теряет свою подпись")

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
        check(files.allSatisfy { $0.kb >= 20 * 1024 }, "все файлы ≥ 20 МБ")
        check(!files.contains { $0.path.contains(".pvm/") || $0.path.contains(".app/") }, "нет кишок пакетов")
        // Из ~/Library разрешены только бэкапы iPhone и известные диски Docker/Rancher — остальное мимо.
        let libOK = ["/MobileSync/Backup/", "com.docker.docker", "rancher-desktop"]
        let stray = files.filter { f in f.path.hasPrefix(lib + "/") && !libOK.contains { f.path.contains($0) } }
        check(stray.isEmpty, "из ~/Library — только ожидаемое")
        if FileManager.default.fileExists(atPath: home + "/Parallels/Windows 11.pvm") {
            check(files.contains { $0.path.hasSuffix("Windows 11.pvm") }, "виртуалка Parallels найдена")
        }
        if FileManager.default.fileExists(atPath: home + "/.colima") {
            check(files.contains { $0.path == home + "/.colima" }, "диск colima найден")
        }
        print("Большие файлы: \(files.count)")
        for f in files.prefix(8) {
            print("  \(human(f.kb).padding(toLength: 9, withPad: " ", startingAt: 0)) \(f.name) — \(f.note.isEmpty ? f.folder : f.note)")
        }

        print(fails == 0 ? "tests OK" : "\(fails) FAIL")
        exit(fails == 0 ? 0 : 1)
    }
}
