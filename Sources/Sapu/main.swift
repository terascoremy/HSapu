import Foundation

let cliArgs = CommandLine.arguments

if cliArgs.contains("--selftest") {
    SelfTest.run()
    exit(0)
}

if let i = cliArgs.firstIndex(of: "--check-update") {
    let cur = i + 1 < cliArgs.count ? cliArgs[i + 1] : appVersion
    switch Updater.check(current: cur) {
    case .available(let u): print("TERSEDIA \(u.version) dmg=\(u.dmgName ?? "-") \(u.url)")
    case .upToDate: print("TERKINI")
    case .failed(let m): print("GAGAL \(m)")
    }
    exit(0)
}

if cliArgs.contains("--selftest-core") {
    CoreSelfTest.run()
    exit(0)
}

if cliArgs.contains("--selftest-hub") {
    HubSelfTest.run()
    exit(0)
}

if cliArgs.contains("--scan") {
    var cats = Catalog.blank()
    for i in cats.indices where cats[i].id != "big" || cliArgs.contains("--big") {
        let t0 = Date()
        cats[i].items = Scanner.scan(cats[i].id)
        print(String(format: "   masa %@: %.1f saat", cats[i].id, Date().timeIntervalSince(t0)))
    }
    let before = cats.reduce(Int64(0)) { $0 + $1.total }
    let removed = Dedupe.apply(&cats)
    let after = cats.reduce(Int64(0)) { $0 + $1.total }
    for c in cats {
        print("== \(c.id): \(c.items.count) item, \(fmt(c.total)) boleh dibuang")
        for it in c.items.prefix(cliArgs.contains("--all") ? 500 : 4) {
            print("   \(fmt(it.size))\t\(it.safety)\t\(it.name)\t\(it.detail)")
        }
    }
    print("Jumlah sebelum nyah-pendua: \(fmt(before)), selepas: \(fmt(after)), \(removed) item dibuang daripada senarai")
    var paths = [String]()
    for c in cats { for it in c.items where it.safety != .locked && Dedupe.isWhole(it.action) { paths.append(it.path) } }
    var overlap = 0
    for p in paths { if paths.contains(where: { $0 != p && p.hasPrefix($0 + "/") }) { overlap += 1 } }
    print("Semakan: \(Set(paths).count == paths.count ? "tiada laluan pendua" : "ADA laluan pendua"), \(overlap) item bertindih")
    exit(0)
}

SapuApp.main()
