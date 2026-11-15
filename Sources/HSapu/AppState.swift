import AppKit
import SwiftUI

struct PendingClean: Identifiable {
    let id = UUID()
    let categoryID: String?
    let title: String
    let groups: [(title: String, items: [CleanItem])]

    var count: Int { groups.reduce(0) { $0 + $1.items.count } }
    var total: Int64 { groups.reduce(0) { $0 + $1.items.reduce(0) { $0 + $1.size } } }
}

@MainActor
final class AppState: ObservableObject {
    @Published var categories: [CleanCategory] = Catalog.blank()
    @Published var selection: Selection = .overview
    @Published var scanning = false
    @Published var scanDone = 0
    @Published var scanTotal = 0
    @Published var scanPending: [String] = []
    @Published var scanStart: Date?
    @Published var hasScanned = false
    @Published var lastScan: Date?
    @Published var cleaning = false
    @Published var cleanProgress: Double = 0
    @Published var cleanLabel = ""
    @Published var lastFreed: Int64?
    @Published var lastWasTrash = false
    @Published var errors: [String] = []
    @Published var showErrors = false
    @Published var pending: PendingClean?
    @Published var diskTotal: Int64 = 0
    @Published var diskFree: Int64 = 0
    @Published var update: UpdateInfo?

    var skipIDs: Set<String> = []
    private var timer: Timer?

    init() {
        refreshDisk()
        loadCache()
    }

    var theme: Theme {
        switch selection {
        case .overview, .settings, .history: return .overview
        case .worktrees: return .worktrees
        case .builds: return .builds
        case .dev: return .dev
        case .simulators: return .sims
        case .category(let id): return categories.first { $0.id == id }?.theme ?? .overview
        }
    }

    var usedFraction: Double {
        diskTotal > 0 ? Double(diskTotal - diskFree) / Double(diskTotal) : 0
    }

    var scanFraction: Double { scanTotal > 0 ? Double(scanDone) / Double(scanTotal) : 0 }

    var totalFound: Int64 { categories.reduce(0) { $0 + $1.total } }
    var totalSelected: Int64 { categories.reduce(0) { $0 + $1.selectedSize } }
    var selectedCount: Int { categories.reduce(0) { $0 + $1.selectedItems.count } }
    var scannedCount: Int { categories.filter { $0.scanned }.count }

    func refreshDisk() {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        if let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]) {
            diskTotal = Int64(v.volumeTotalCapacity ?? 0)
            diskFree = v.volumeAvailableCapacityForImportantUsage ?? 0
        }
    }

    // MARK: cache

    /// Papar hasil imbasan terakhir serta-merta, supaya tak perlu tunggu imbasan baru.
    func loadCache() {
        guard let snap = Store.load(ScanSnapshot.self, "scan-cache.json") else { return }
        let fm = FileManager.default
        for i in categories.indices {
            guard let items = snap.items[categories[i].id] else { continue }
            // Buang item yang sudah tiada di cakera sejak imbasan terakhir.
            categories[i].items = Exclusions.filter(items).filter { fm.fileExists(atPath: $0.path) }
            categories[i].scanned = true
        }
        hasScanned = true
        lastScan = snap.date
    }

    func saveCache() {
        guard skipIDs.isEmpty else { return }
        var dict = [String: [CleanItem]]()
        for c in categories where c.scanned { dict[c.id] = c.items }
        Store.save(ScanSnapshot(date: lastScan ?? Date(), items: dict), "scan-cache.json")
    }

    var cacheAge: TimeInterval? { lastScan.map { Date().timeIntervalSince($0) } }

    /// Dipanggil bila app dibuka: imbas senyap di latar jika data lebih 30 minit.
    func autoRefresh() {
        if let age = cacheAge, age < 1800 { return }
        scan(background: true)
    }

    // MARK: scan

    func scan(background: Bool = false, completion: ((Int64) -> Void)? = nil) {
        guard !scanning, !cleaning else { return }
        scanning = true
        if !background { lastFreed = nil }
        if !hasScanned {
            for i in categories.indices {
                categories[i].items = []
                categories[i].scanned = false
            }
        }
        let ids = categories.map { $0.id }
        let skip = skipIDs
        scanDone = 0
        scanTotal = ids.filter { !skip.contains($0) }.count
        scanPending = categories.filter { !skip.contains($0.id) }.map { $0.title }
        scanStart = Date()
        let qos: DispatchQoS.QoSClass = background ? .utility : .userInitiated
        Scanner.sizeMaxAge = background ? 3 * 3600 : 900
        Task {
            await withTaskGroup(of: (String, [CleanItem]).self) { group in
                for id in ids {
                    group.addTask {
                        if skip.contains(id) { return (id, []) }
                        return await withCheckedContinuation { cont in
                            DispatchQueue.global(qos: qos).async {
                                cont.resume(returning: (id, Scanner.scan(id)))
                            }
                        }
                    }
                }
                for await (id, found) in group {
                    guard let i = self.categories.firstIndex(where: { $0.id == id }) else { continue }
                    if !skip.contains(id) {
                        self.scanDone += 1
                        let title = self.categories[i].title
                        self.scanPending.removeAll { $0 == title }
                    }
                    // Kekalkan pilihan pengguna untuk item yang sama.
                    var chosen = [String: Bool]()
                    for it in self.categories[i].items { chosen[it.path] = it.selected }
                    var items = Exclusions.filter(found)
                    for j in items.indices {
                        if let s = chosen[items[j].path] { items[j].selected = s && items[j].safety != .locked }
                    }
                    withAnimation(.easeOut(duration: 0.25)) {
                        self.categories[i].items = items
                        self.categories[i].scanned = true
                    }
                }
            }
            Dedupe.apply(&self.categories)
            self.scanning = false
            self.scanPending = []
            self.hasScanned = true
            self.lastScan = Date()
            self.refreshDisk()
            self.saveCache()
            completion?(self.totalFound)
        }
    }

    // MARK: selection

    func toggle(_ categoryID: String, _ itemID: UUID) {
        guard let c = categories.firstIndex(where: { $0.id == categoryID }),
              let i = categories[c].items.firstIndex(where: { $0.id == itemID }),
              categories[c].items[i].safety != .locked else { return }
        categories[c].items[i].selected.toggle()
    }

    func select(_ categoryID: String, where pred: (CleanItem) -> Bool) {
        guard let c = categories.firstIndex(where: { $0.id == categoryID }) else { return }
        for i in categories[c].items.indices {
            let it = categories[c].items[i]
            categories[c].items[i].selected = it.safety != .locked && pred(it)
        }
    }

    /// Tambah ke senarai jangan sentuh dan keluarkan dari senarai semasa.
    func exclude(_ path: String) {
        Exclusions.add(path)
        for c in categories.indices {
            categories[c].items.removeAll { Exclusions.isExcluded($0.path) }
        }
        saveCache()
    }

    // MARK: clean

    /// Buka lembaran pratonton. Pembersihan hanya bermula selepas pengguna sahkan.
    func requestClean(categoryID: String?) {
        guard !cleaning, !scanning else { return }
        var groups = [(title: String, items: [CleanItem])]()
        for c in categories where categoryID == nil || c.id == categoryID {
            let sel = c.selectedItems
            if !sel.isEmpty { groups.append((c.title, sel)) }
        }
        guard !groups.isEmpty else { return }
        let title = categoryID.flatMap { id in categories.first { $0.id == id }?.title } ?? "Semua kategori"
        pending = PendingClean(categoryID: categoryID, title: title, groups: groups)
    }

    func clean(categoryID: String?, toTrash: Bool = false) {
        guard !cleaning, !scanning else { return }
        var work = [(cat: String, item: CleanItem)]()
        for c in categories where categoryID == nil || c.id == categoryID {
            for it in c.selectedItems { work.append((c.id, it)) }
        }
        guard !work.isEmpty else { return }
        cleaning = true
        cleanProgress = 0
        errors = []
        Task {
            var freed: Int64 = 0
            var done = 0
            var record = [HistoryItem]()
            let titles = Dictionary(uniqueKeysWithValues: self.categories.map { ($0.id, $0.title) })
            for (n, w) in work.enumerated() {
                self.cleanLabel = w.item.name
                let err: String? = await withCheckedContinuation { cont in
                    DispatchQueue.global(qos: .userInitiated).async {
                        cont.resume(returning: Cleaner.perform(w.item, toTrash: toTrash))
                    }
                }
                if let err {
                    self.errors.append(err)
                } else {
                    freed += w.item.size
                    done += 1
                    record.append(HistoryItem(name: w.item.name, category: titles[w.cat] ?? w.cat,
                                              how: actionLabel(w.item, trash: toTrash), size: w.item.size))
                    if let c = self.categories.firstIndex(where: { $0.id == w.cat }) {
                        self.categories[c].items.removeAll { $0.id == w.item.id }
                    }
                }
                self.cleanProgress = Double(n + 1) / Double(work.count)
            }
            self.cleaning = false
            self.lastFreed = freed
            self.lastWasTrash = toTrash
            self.refreshDisk()
            self.showErrors = !self.errors.isEmpty
            self.saveCache()
            History.record(freed: freed, count: done, note: toTrash ? "Pembersih (ke Tong Sampah)" : "Pembersih", items: record)
        }
    }

    // MARK: pemantauan latar belakang

    func startMonitor() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        tick()
        checkUpdatesIfDue()
    }

    func tick() {
        refreshDisk()
        if Prefs.lowDiskAlert, diskFree < Int64(Prefs.lowDiskGB) * 1_000_000_000,
           Prefs.lastLowDiskNotice.map({ Date().timeIntervalSince($0) > 86400 }) ?? true {
            Prefs.lastLowDiskNotice = Date()
            Notifier.send(tr("Ruang cakera rendah"), tr("Tinggal \(fmt(diskFree)). Buka HSapu untuk bersihkan."))
        }
        let days = Prefs.scanEveryDays
        if days > 0, !scanning, !cleaning,
           Prefs.lastAutoScan.map({ Date().timeIntervalSince($0) > Double(days) * 86400 }) ?? true {
            Prefs.lastAutoScan = Date()
            scan(background: true) { found in
                if found > 0 { Notifier.send(tr("HSapu jumpa \(fmt(found)) boleh dibersihkan"), tr("Buka HSapu untuk semak dan bersihkan.")) }
            }
        }
    }

    // MARK: kemas kini

    func checkUpdatesIfDue() {
        guard Prefs.checkUpdates else { return }
        if let last = Prefs.lastUpdateCheck, Date().timeIntervalSince(last) < 86400 { return }
        checkUpdates()
    }

    func checkUpdates(completion: ((UpdateResult) -> Void)? = nil) {
        Task.detached(priority: .utility) {
            let r = Updater.check()
            await MainActor.run {
                Prefs.lastUpdateCheck = Date()
                if case .available(let info) = r { self.update = info } else { self.update = nil }
                completion?(r)
            }
        }
    }

    // MARK: debug snapshots

    func runShots(to dir: String, hub: HubState, sims: SimState) {
        skipIDs = ["big"]
        scan()
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if self.scanning { self.snapshot(dir + "/0-scanning.png") }
            while self.scanning { try? await Task.sleep(nanoseconds: 300_000_000) }
            try? await Task.sleep(nanoseconds: 900_000_000)
            self.snapshot(dir + "/1-overview.png")
            hub.refreshAll()
            sims.refresh()
            // Tunggu sehingga hub siap (had 150 saat).
            var waited = 0.0
            while waited < 150 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                waited += 0.5
                let hubDone = !hub.loadingWT && !hub.loadingApps && !hub.worktrees.contains { $0.size == nil }
                if hubDone && !sims.loading && !sims.sizing { break }
            }
            let shots: [(Selection, String)] = [(.worktrees, "worktrees"), (.builds, "builds"), (.dev, "dev"),
                                                (.simulators, "simulators"), (.settings, "settings")]
            for (n, s) in shots.enumerated() {
                self.selection = s.0
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                self.snapshot(dir + "/\(n + 2)-\(s.1).png")
            }
            self.selection = .category("downloads")
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self.snapshot(dir + "/9-downloads.png")
            self.selection = .category("worktree")
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self.snapshot(dir + "/9b-worktree.png")
            // Halaman sejarah dengan data contoh dalam folder sementara, supaya data sebenar tak disentuh.
            let demo = NSTemporaryDirectory() + "sapu-demo-" + UUID().uuidString
            try? FileManager.default.createDirectory(atPath: demo, withIntermediateDirectories: true)
            AppSupport.override = demo
            var fake = [HistoryEntry]()
            let cal = Calendar.current
            let names = [("DerivedData", "Xcode", 6_200_000_000), ("Cache Gradle", "Cache developer", 3_100_000_000),
                         ("hrwork_mobile/fix-login", "Worktree git", 1_400_000_000), ("Data iPhone 17 Pro", "Simulator", 5_000_000_000)]
            for back in [0, 0, 1, 3, 4, 7, 9, 12, 15, 21] {
                let t = cal.date(byAdding: .day, value: -back, to: Date())!.addingTimeInterval(Double(-back * 997 % 7200))
                let items = names.prefix(2 + back % 3).map { HistoryItem(name: $0.0, category: $0.1, how: "Dipadam terus", size: Int64($0.2) / Int64(1 + back % 2)) }
                fake.append(HistoryEntry(date: t, freed: items.reduce(0) { $0 + $1.size }, count: items.count, note: "Pembersih", items: items))
            }
            fake.append(HistoryEntry(date: Date().addingTimeInterval(-86400 * 30), freed: 2_000_000_000, count: 1, note: "Worktree", items: nil))
            Store.save(fake, "history.json")
            self.selection = .history
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            self.snapshot(dir + "/8-history.png")
            AppSupport.override = nil
            try? FileManager.default.removeItem(atPath: demo)
            if let c = self.categories.first(where: { !$0.selectedItems.isEmpty }) {
                self.selection = .category(c.id)
                self.requestClean(categoryID: c.id)
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                self.snapshot(dir + "/7-preview.png")
                self.pending = nil
            }
            exit(0)
        }
    }

    func snapshot(_ path: String) {
        // Lembaran (sheet) ialah tetingkap berasingan; ambil tetingkap paling atas yang kelihatan.
        let wins = NSApp.windows.filter { $0.isVisible && $0.contentView != nil }
        guard let w = wins.last(where: { $0.isSheet }) ?? wins.first(where: { $0.isVisible }), let v = w.contentView,
              let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
        v.cacheDisplay(in: v.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
