import AppKit
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var categories: [CleanCategory] = Catalog.blank()
    @Published var selection: Selection = .overview
    @Published var scanning = false
    @Published var hasScanned = false
    @Published var cleaning = false
    @Published var cleanProgress: Double = 0
    @Published var cleanLabel = ""
    @Published var lastFreed: Int64?
    @Published var errors: [String] = []
    @Published var showErrors = false
    @Published var diskTotal: Int64 = 0
    @Published var diskFree: Int64 = 0

    var skipIDs: Set<String> = []

    init() { refreshDisk() }

    var theme: Theme {
        switch selection {
        case .overview: return .overview
        case .worktrees: return .worktrees
        case .builds: return .builds
        case .dev: return .dev
        case .category(let id): return categories.first { $0.id == id }?.theme ?? .overview
        }
    }

    var usedFraction: Double {
        diskTotal > 0 ? Double(diskTotal - diskFree) / Double(diskTotal) : 0
    }

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

    // MARK: scan

    func scan() {
        guard !scanning, !cleaning else { return }
        scanning = true
        lastFreed = nil
        for i in categories.indices {
            categories[i].items = []
            categories[i].scanned = false
        }
        let ids = categories.map { $0.id }
        let skip = skipIDs
        Task {
            await withTaskGroup(of: (String, [CleanItem]).self) { group in
                for id in ids {
                    group.addTask {
                        if skip.contains(id) { return (id, []) }
                        return await withCheckedContinuation { cont in
                            DispatchQueue.global(qos: .userInitiated).async {
                                cont.resume(returning: (id, Scanner.scan(id)))
                            }
                        }
                    }
                }
                for await (id, items) in group {
                    if let i = self.categories.firstIndex(where: { $0.id == id }) {
                        withAnimation(.easeOut(duration: 0.25)) {
                            self.categories[i].items = items
                            self.categories[i].scanned = true
                        }
                    }
                }
            }
            Dedupe.apply(&self.categories)
            self.scanning = false
            self.hasScanned = true
            self.refreshDisk()
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

    // MARK: clean

    func clean(categoryID: String?) {
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
            for (n, w) in work.enumerated() {
                self.cleanLabel = w.item.name
                let err: String? = await withCheckedContinuation { cont in
                    DispatchQueue.global(qos: .userInitiated).async {
                        cont.resume(returning: Cleaner.perform(w.item))
                    }
                }
                if let err {
                    self.errors.append(err)
                } else {
                    freed += w.item.size
                    if let c = self.categories.firstIndex(where: { $0.id == w.cat }) {
                        self.categories[c].items.removeAll { $0.id == w.item.id }
                    }
                }
                self.cleanProgress = Double(n + 1) / Double(work.count)
            }
            self.cleaning = false
            self.lastFreed = freed
            self.refreshDisk()
            self.showErrors = !self.errors.isEmpty
        }
    }

    // MARK: debug snapshots

    func runShots(to dir: String, hub: HubState) {
        skipIDs = ["big"]
        scan()
        Task {
            while self.scanning { try? await Task.sleep(nanoseconds: 300_000_000) }
            try? await Task.sleep(nanoseconds: 900_000_000)
            self.snapshot(dir + "/1-overview.png")
            hub.refreshAll()
            try? await Task.sleep(nanoseconds: 90_000_000_000)
            let shots: [(Selection, String)] = [(.worktrees, "worktrees"), (.builds, "builds"), (.dev, "dev")]
            for (n, s) in shots.enumerated() {
                self.selection = s.0
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                self.snapshot(dir + "/\(n + 2)-\(s.1).png")
            }
            NSApp.terminate(nil)
        }
    }

    func snapshot(_ path: String) {
        guard let w = NSApp.windows.first(where: { $0.isVisible }), let v = w.contentView,
              let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
        v.cacheDisplay(in: v.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
