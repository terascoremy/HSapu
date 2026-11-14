import AppKit
import Foundation

/// Ujian untuk ciri 1.1: cache, kecualian, sejarah, pratonton, Tong Sampah, simulator, kemas kini.
/// Guna folder dan UserDefaults sementara; data sebenar tak disentuh.
enum CoreSelfTest {
    static func run() {
        var ok = true
        func check(_ label: String, _ cond: Bool) {
            print((cond ? "PASS " : "FAIL ") + label)
            if !cond { ok = false }
        }
        let fm = FileManager.default
        let root = NSTemporaryDirectory() + "sapu-coretest-" + UUID().uuidString
        try? fm.createDirectory(atPath: root + "/support", withIntermediateDirectories: true)
        let suite = "app.sapu.test." + UUID().uuidString
        let realDefaults = Prefs.defaults
        Prefs.defaults = UserDefaults(suiteName: suite)!
        AppSupport.override = root + "/support"
        SizeCache.reset()
        defer {
            Prefs.defaults.removePersistentDomain(forName: suite)
            Prefs.defaults = realDefaults
            AppSupport.override = nil
            SizeCache.reset()
            try? fm.removeItem(atPath: root)
        }

        // --- kecualian
        Exclusions.add(root + "/keep")
        check("kecualian: laluan sama", Exclusions.isExcluded(root + "/keep"))
        check("kecualian: anak folder", Exclusions.isExcluded(root + "/keep/sub/file"))
        check("kecualian: induk yang mengandungi folder dikecualikan", Exclusions.isExcluded(root))
        check("kecualian: nama berawalan sama tak terkena", !Exclusions.isExcluded(root + "/keeper"))
        Exclusions.add(root + "/keep")
        check("kecualian: tiada pendua", Exclusions.list.count == 1)
        Exclusions.remove(root + "/keep")
        check("kecualian: dibuang semula", Exclusions.list.isEmpty && !Exclusions.isExcluded(root + "/keep"))

        // --- sejarah
        History.record(freed: 5_000, count: 2, note: "ujian a")
        History.record(freed: 7_000, count: 0, note: "tak direkod")
        History.record(freed: 3_000, count: 1, note: "ujian b")
        check("sejarah: jumlah dan kiraan betul", History.totalFreed == 8_000 && History.all().count == 2)
        check("sejarah: terbaru dahulu", History.all().first?.note == "ujian b")

        // --- cache saiz
        let sizedDir = root + "/sized"
        try? fm.createDirectory(atPath: sizedDir, withIntermediateDirectories: true)
        fm.createFile(atPath: sizedDir + "/f", contents: Data(count: 100_000))
        SizeCache.put([sizedDir: 123_456_789])
        check("cache saiz: guna nilai segar tanpa du", Scanner.cachedSizes([sizedDir])[sizedDir] == 123_456_789)
        check("cache saiz: nilai lapuk tak dianggap segar", SizeCache.fresh([sizedDir], maxAge: -1).isEmpty && SizeCache.any([sizedDir])[sizedDir] == 123_456_789)
        SizeCache.reset()
        check("cache saiz: kekal selepas dimuat semula dari fail", SizeCache.any([sizedDir])[sizedDir] == 123_456_789)

        // --- Codable semua jenis tindakan
        let actions: [CleanAction] = [.delete, .deleteContents, .trash, .trashList(["/a", "/b"]), .worktree(repo: "/r"), .simulatorErase]
        let items = actions.enumerated().map { CleanItem(name: "n\($0.offset)", path: "/p\($0.offset)", detail: "d", size: Int64($0.offset) * 10, safety: .review, action: $0.element, selected: $0.offset % 2 == 0) }
        Store.save(ScanSnapshot(date: Date(), items: ["x": items]), "rt.json")
        let back = Store.load(ScanSnapshot.self, "rt.json")?.items["x"] ?? []
        var same = back.count == items.count
        for (a, b) in zip(items, back) { same = same && a.name == b.name && a.path == b.path && a.size == b.size && a.selected == b.selected && a.safety == b.safety }
        check("codable: semua item pulang sama", same)
        if back.count == 6, case .trashList(let l) = back[3].action, case .worktree(let r) = back[4].action {
            check("codable: data dalam tindakan kekal", l == ["/a", "/b"] && r == "/r")
        } else {
            check("codable: data dalam tindakan kekal", false)
        }

        // --- Tong Sampah (alih, bukan padam)
        let trashName = "sapu-coretest-" + UUID().uuidString
        let f1 = root + "/" + trashName
        fm.createFile(atPath: f1, contents: Data("x".utf8))
        let trashPath = NSHomeDirectory() + "/.Trash/" + trashName
        let toTrash = Cleaner.perform(CleanItem(name: "t", path: f1, detail: "", size: 1, safety: .safe, action: .delete, selected: true), toTrash: true)
        check("Tong Sampah: tiada ralat", toTrash == nil)
        check("Tong Sampah: fail asal dialih dan boleh dipulihkan", !fm.fileExists(atPath: f1) && fm.fileExists(atPath: trashPath))
        try? fm.removeItem(atPath: trashPath)

        let dirT = root + "/contents"
        let childName = "sapu-child-" + UUID().uuidString
        try? fm.createDirectory(atPath: dirT, withIntermediateDirectories: true)
        fm.createFile(atPath: dirT + "/" + childName, contents: Data("x".utf8))
        let r2 = Cleaner.perform(CleanItem(name: "c", path: dirT, detail: "", size: 1, safety: .safe, action: .deleteContents, selected: true), toTrash: true)
        check("Tong Sampah: deleteContents alih isi, folder kekal", r2 == nil && fm.fileExists(atPath: dirT) && !fm.fileExists(atPath: dirT + "/" + childName)
              && fm.fileExists(atPath: NSHomeDirectory() + "/.Trash/" + childName))
        try? fm.removeItem(atPath: NSHomeDirectory() + "/.Trash/" + childName)

        // --- AppState: cache, pratonton, bersih, sejarah, kecualian
        let cacheFile = root + "/cached-file"
        fm.createFile(atPath: cacheFile, contents: Data(count: 2048))
        let gone = root + "/sudah-tiada"
        let skipMe = root + "/dikecualikan"
        fm.createFile(atPath: skipMe, contents: Data(count: 10))
        Exclusions.add(skipMe)
        let snapItems = [
            CleanItem(name: "ada", path: cacheFile, detail: "", size: 2048, safety: .safe, action: .delete, selected: true),
            CleanItem(name: "tiada", path: gone, detail: "", size: 999, safety: .safe, action: .delete, selected: true),
            CleanItem(name: "kecuali", path: skipMe, detail: "", size: 10, safety: .safe, action: .delete, selected: true),
        ]
        Store.save(ScanSnapshot(date: Date().addingTimeInterval(-60), items: ["system": snapItems]), "scan-cache.json")

        MainActor.assumeIsolated {
            let state = AppState()
            let sys = state.categories.first { $0.id == "system" }
            check("cache imbasan: dimuat serta-merta", state.hasScanned && sys?.scanned == true)
            check("cache imbasan: hanya item yang masih wujud dan tak dikecualikan", sys?.items.map { $0.name } == ["ada"])
            check("cache imbasan: umur direkod", (state.cacheAge ?? 9999) < 600)

            state.requestClean(categoryID: "system")
            check("pratonton: dibina daripada item terpilih", state.pending?.count == 1 && state.pending?.total == 2048)
            state.pending = nil
            state.requestClean(categoryID: "xcode")
            check("pratonton: kategori kosong tiada lembaran", state.pending == nil)

            state.clean(categoryID: "system", toTrash: false)
            let end = Date().addingTimeInterval(10)
            while Date() < end, state.cleaning || fm.fileExists(atPath: cacheFile) { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            check("bersih: item dipadam", !fm.fileExists(atPath: cacheFile))
            check("bersih: dikeluarkan dari senarai dan dibebaskan direkod", state.categories.first { $0.id == "system" }?.items.isEmpty == true && state.lastFreed == 2048)
            check("bersih: sejarah ditambah", History.all().contains { $0.note == "Pembersih" && $0.freed == 2048 })
            check("bersih: cache dikemas kini", Store.load(ScanSnapshot.self, "scan-cache.json")?.items["system"]?.isEmpty == true)

            let keep = CleanItem(name: "x", path: root + "/lagi", detail: "", size: 1, safety: .safe, action: .delete, selected: true)
            state.categories[0].items = [keep]
            state.exclude(keep.path)
            check("kecualian: item dikeluarkan serta-merta dan disimpan", state.categories[0].items.isEmpty && Exclusions.isExcluded(keep.path))
        }

        // --- kemas kini
        check("versi: 1.10.0 lebih baru daripada 1.9.9", Updater.newer("v1.10.0", than: "1.9.9"))
        check("versi: sama bukan lebih baru", !Updater.newer("1.1.0", than: "1.1.0") && !Updater.newer("1.1", than: "1.1.0"))
        check("versi: lebih lama ditolak", !Updater.newer("1.0.9", than: "1.1.0"))
        let json = #"{"tagName":"v1.2.0","url":"https://x/y","body":"nota","assets":[{"name":"Sapu-1.2.0.dmg"}]}"#
        if case .available(let i) = Updater.parse(json, current: "1.1.0") {
            check("kemas kini: keluaran baru dikesan dengan dmg", i.version == "1.2.0" && i.dmgName == "Sapu-1.2.0.dmg" && i.notes == "nota")
        } else { check("kemas kini: keluaran baru dikesan dengan dmg", false) }
        if case .upToDate = Updater.parse(json, current: "1.2.0") { check("kemas kini: versi sama dikesan terkini", true) } else { check("kemas kini: versi sama dikesan terkini", false) }
        if case .failed = Updater.parse("bukan json", current: "1.0.0") { check("kemas kini: jawapan rosak ditangani", true) } else { check("kemas kini: jawapan rosak ditangani", false) }

        // --- simulator: penghurai
        check("simulator: nama runtime cantik", SimScan.pretty("com.apple.CoreSimulator.SimRuntime.iOS-26-5") == "iOS 26.5"
              && SimScan.pretty("com.apple.CoreSimulator.SimRuntime.watchOS-11-2") == "watchOS 11.2")
        let devJSON = #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-5":[{"udid":"U1","name":"iPhone A","state":"Booted","isAvailable":true},{"udid":"U2","name":"iPad B","state":"Shutdown","isAvailable":true}],"com.apple.CoreSimulator.SimRuntime.iOS-17-0":[{"udid":"U3","name":"Lama","state":"Shutdown","isAvailable":false}]}}"#
        let devs = SimScan.parseDevices(devJSON)
        check("simulator: peranti dihuraikan", devs.count == 3 && devs.filter { $0.booted }.count == 1 && devs.filter { !$0.available }.count == 1)
        let rtJSON = #"{"ID-1":{"runtimeIdentifier":"com.apple.CoreSimulator.SimRuntime.iOS-26-5","version":"26.5","build":"23F77","sizeBytes":8494282293,"deletable":true,"platformIdentifier":"com.apple.platform.iphonesimulator"}}"#
        let rts = SimScan.parseRuntimes(rtJSON, devices: devs)
        check("simulator: runtime dihuraikan dengan bilangan peranti", rts.count == 1 && rts[0].name == "iOS 26.5" && rts[0].devices == 2 && rts[0].size == 8494282293 && rts[0].id == "ID-1")

        // --- simulator sebenar: baca sahaja
        if fm.isExecutableFile(atPath: SimScan.xcrun) {
            let real = SimScan.ctl(["list", "devices", "-j"], timeout: 40)
            let names = SimScan.parseRuntimeNames(SimScan.ctl(["list", "runtimes", "-j"], timeout: 40).out)
            let realDevs = SimScan.parseDevices(real.out, runtimeNames: names)
            check("simulator sebenar: senarai peranti dibaca (\(realDevs.count))", real.status == 0 && !realDevs.isEmpty)
            let realRT = SimScan.parseRuntimes(SimScan.ctl(["runtime", "list", "-j"], timeout: 40).out, devices: realDevs)
            check("simulator sebenar: senarai runtime dibaca (\(realRT.count))", !realRT.isEmpty && realRT.allSatisfy { $0.size > 0 })

            // Kitar hayat penuh pada peranti ujian sendiri: cipta, kotorkan, erase, padam.
            let rtID = names.keys.filter { $0.contains("iOS") && !$0.contains("iPhone") }.sorted().last
            let testName = "SapuTest-" + String(UUID().uuidString.prefix(8))
            if let rtID {
                let made = SimScan.ctl(["create", testName, "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro", rtID])
                let udid = made.out.trimmingCharacters(in: .whitespacesAndNewlines)
                if made.status == 0, udid.count > 20 {
                    var d = SimDevice(udid: udid, name: testName, runtimeID: rtID, runtimeName: "", state: "Shutdown", available: true, size: nil)
                    check("simulator ujian: dicipta dalam senarai", SimScan.parseDevices(SimScan.ctl(["list", "devices", "-j"]).out).contains { $0.udid == udid })
                    fm.createFile(atPath: d.dataPath + "/data/Documents/sapu-junk.bin", contents: Data(count: 3_000_000))
                    try? fm.createDirectory(atPath: d.dataPath + "/data/Documents", withIntermediateDirectories: true)
                    fm.createFile(atPath: d.dataPath + "/data/Documents/sapu-junk.bin", contents: Data(count: 3_000_000))
                    d.size = Scanner.size(d.dataPath)
                    let e = SimState.eraseOne(d)
                    check("simulator ujian: erase berjaya", e.error == nil)
                    check("simulator ujian: data dipadam dan baki dikira", !fm.fileExists(atPath: d.dataPath + "/data/Documents/sapu-junk.bin") && e.freed >= 1_000_000)
                    let del = SimScan.ctl(["delete", udid])
                    check("simulator ujian: padam peranti", del.status == 0 && !SimScan.parseDevices(SimScan.ctl(["list", "devices", "-j"]).out).contains { $0.udid == udid })
                } else {
                    print("SKIP simulator ujian: tak dapat cipta peranti (\(made.out.prefix(80)))")
                }
            } else {
                print("SKIP simulator ujian: tiada runtime iOS")
            }
        } else {
            print("SKIP simulator: xcrun tiada")
        }

        // --- akses dan log masuk (tak boleh ranap)
        _ = Access.fullDisk()
        _ = LoginItem.enabled
        check("akses cakera penuh: semakan tak ranap", true)

        print(ok ? "SEMUA LULUS" : "ADA YANG GAGAL")
        if !ok { exit(1) }
    }
}
