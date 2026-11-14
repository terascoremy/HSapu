import Foundation

struct SimRuntime: Identifiable {
    let id: String          // pengecam imej runtime (untuk `simctl runtime delete`)
    let runtimeID: String   // com.apple.CoreSimulator.SimRuntime.iOS-26-5
    let name: String
    let build: String
    let size: Int64
    var devices: Int
    let deletable: Bool
}

struct SimDevice: Identifiable {
    var id: String { udid }
    let udid: String
    let name: String
    let runtimeID: String
    let runtimeName: String
    let state: String
    let available: Bool
    var size: Int64?

    var booted: Bool { state == "Booted" || state == "Booting" }
    var dataPath: String { Scanner.home + "/Library/Developer/CoreSimulator/Devices/" + udid }
}

enum SimScan {
    static let xcrun = "/usr/bin/xcrun"

    static func ctl(_ args: [String], timeout: Double = 60) -> (status: Int32, out: String) {
        Shell.run(xcrun, ["simctl"] + args, mergeErr: true, timeout: timeout)
    }

    /// "com.apple.CoreSimulator.SimRuntime.iOS-26-5" -> "iOS 26.5"
    static func pretty(_ runtimeID: String) -> String {
        let last = runtimeID.split(separator: ".").last.map(String.init) ?? runtimeID
        let bits = last.split(separator: "-").map(String.init)
        guard let platform = bits.first else { return last }
        let nums = bits.dropFirst().filter { Int($0) != nil }
        return nums.isEmpty ? last : platform + " " + nums.joined(separator: ".")
    }

    private static func object(_ json: String) -> [String: Any]? {
        guard let d = json.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }

    static func parseDevices(_ json: String, runtimeNames: [String: String] = [:]) -> [SimDevice] {
        guard let o = object(json), let groups = o["devices"] as? [String: [[String: Any]]] else { return [] }
        var out = [SimDevice]()
        for (rt, list) in groups {
            for d in list {
                guard let udid = d["udid"] as? String, let name = d["name"] as? String else { continue }
                out.append(SimDevice(udid: udid, name: name, runtimeID: rt, runtimeName: runtimeNames[rt] ?? pretty(rt),
                                     state: d["state"] as? String ?? "Shutdown", available: d["isAvailable"] as? Bool ?? true, size: nil))
            }
        }
        return out
    }

    static func parseRuntimeNames(_ json: String) -> [String: String] {
        guard let o = object(json), let list = o["runtimes"] as? [[String: Any]] else { return [:] }
        var m = [String: String]()
        for r in list { if let id = r["identifier"] as? String, let n = r["name"] as? String { m[id] = n } }
        return m
    }

    static func platformName(_ p: String) -> String {
        if p.contains("iphone") { return "iOS" }
        if p.contains("appletv") { return "tvOS" }
        if p.contains("watch") { return "watchOS" }
        if p.contains("xr") { return "visionOS" }
        return "Runtime"
    }

    static func parseRuntimes(_ json: String, devices: [SimDevice]) -> [SimRuntime] {
        guard let o = object(json) else { return [] }
        var out = [SimRuntime]()
        for (id, v) in o {
            guard let r = v as? [String: Any], let rid = r["runtimeIdentifier"] as? String else { continue }
            let version = r["version"] as? String ?? ""
            let size = (r["sizeBytes"] as? NSNumber)?.int64Value ?? 0
            out.append(SimRuntime(id: id, runtimeID: rid,
                                  name: platformName(r["platformIdentifier"] as? String ?? "") + " " + version,
                                  build: r["build"] as? String ?? "", size: size,
                                  devices: devices.filter { $0.runtimeID == rid }.count,
                                  deletable: r["deletable"] as? Bool ?? false))
        }
        return out.sorted { $0.size > $1.size }
    }
}

@MainActor
final class SimState: ObservableObject {
    @Published var runtimes: [SimRuntime] = []
    @Published var devices: [SimDevice] = []
    @Published var loading = false
    @Published var sizing = false
    @Published var busy = false
    @Published var message: String?
    @Published var loaded = false

    var devicesSize: Int64 { devices.reduce(0) { $0 + ($1.size ?? 0) } }
    var runtimesSize: Int64 { runtimes.reduce(0) { $0 + $1.size } }
    var sizesReady: Bool { !devices.isEmpty && !devices.contains { $0.size == nil } }
    var bootedCount: Int { devices.filter { $0.booted }.count }
    var unavailable: [SimDevice] { devices.filter { !$0.available } }
    var erasable: [SimDevice] { devices.filter { !$0.booted && $0.available } }

    func refresh() {
        guard !loading, !busy else { return }
        loading = true
        let previous = Dictionary(devices.compactMap { d in d.size.map { (d.udid, $0) } }, uniquingKeysWith: { a, _ in a })
        Task.detached(priority: .userInitiated) {
            let dev = SimScan.ctl(["list", "devices", "-j"], timeout: 40)
            let names = SimScan.parseRuntimeNames(SimScan.ctl(["list", "runtimes", "-j"], timeout: 40).out)
            var devices = SimScan.parseDevices(dev.out, runtimeNames: names)
            let cached = SizeCache.any(devices.map { $0.dataPath })
            for i in devices.indices {
                devices[i].size = previous[devices[i].udid] ?? cached[devices[i].dataPath]
            }
            let runtimes = SimScan.parseRuntimes(SimScan.ctl(["runtime", "list", "-j"], timeout: 40).out, devices: devices)
            let found = devices
            await MainActor.run {
                self.devices = found.sorted { ($0.size ?? 0) > ($1.size ?? 0) }
                self.runtimes = runtimes
                self.loading = false
                self.loaded = true
                self.loadSizes()
            }
        }
    }

    func loadSizes() {
        guard !sizing else { return }
        sizing = true
        let paths = devices.map { $0.dataPath }
        Task.detached(priority: .utility) {
            let sizes = Scanner.cachedSizes(paths, maxAge: 3600)
            await MainActor.run {
                for i in self.devices.indices { self.devices[i].size = sizes[self.devices[i].dataPath] ?? self.devices[i].size }
                self.devices.sort { ($0.size ?? 0) > ($1.size ?? 0) }
                self.sizing = false
            }
        }
    }

    private func run(_ label: String, work: @escaping () -> (freed: Int64, count: Int, error: String?, items: [HistoryItem])) {
        guard !busy else { return }
        busy = true
        message = nil
        Task.detached(priority: .userInitiated) {
            let r = work()
            await MainActor.run {
                self.busy = false
                SizeCache.invalidate(Scanner.home + "/Library/Developer/CoreSimulator")
                if let e = r.error {
                    self.message = e
                } else {
                    self.message = "\(label) siap" + (r.freed > 0 ? ", \(fmt(r.freed)) dibebaskan." : ".")
                    History.record(freed: r.freed, count: r.count, note: "Simulator: \(label)", items: r.items)
                }
                self.refresh()
            }
        }
    }

    nonisolated private static func sizeNow(_ path: String) -> Int64 {
        let s = Scanner.size(path)
        SizeCache.put([path: s])
        return s
    }

    nonisolated static func eraseOne(_ d: SimDevice) -> (freed: Int64, error: String?) {
        let before = d.size ?? Scanner.size(d.dataPath)
        let r = SimScan.ctl(["erase", d.udid])
        if r.status != 0 { return (0, "\(d.name): \(r.out.trimmingCharacters(in: .whitespacesAndNewlines))") }
        return (max(0, before - sizeNow(d.dataPath)), nil)
    }

    func erase(_ d: SimDevice) {
        guard !d.booted else { return }
        run("Erase \(d.name)") {
            let r = Self.eraseOne(d)
            return (r.freed, r.error == nil ? 1 : 0, r.error,
                    r.error == nil ? [HistoryItem(name: d.name, category: "Simulator", how: "Di-erase", size: r.freed)] : [])
        }
    }

    func delete(_ d: SimDevice) {
        guard !d.booted else { return }
        run("Padam \(d.name)") {
            let before = d.size ?? Scanner.size(d.dataPath)
            let r = SimScan.ctl(["delete", d.udid])
            if r.status != 0 { return (0, 0, "\(d.name): \(r.out.trimmingCharacters(in: .whitespacesAndNewlines))", []) }
            return (before, 1, nil, [HistoryItem(name: d.name, category: "Simulator", how: "Peranti dipadam", size: before)])
        }
    }

    func eraseAllShutdown() {
        let list = erasable
        run("Erase \(list.count) simulator") {
            var freed: Int64 = 0
            var done = 0
            var errors = [String]()
            var items = [HistoryItem]()
            for d in list {
                let r = Self.eraseOne(d)
                freed += r.freed
                if let e = r.error { errors.append(e) } else {
                    done += 1
                    items.append(HistoryItem(name: d.name, category: "Simulator", how: "Di-erase", size: r.freed))
                }
            }
            return (freed, done, errors.isEmpty ? nil : errors.prefix(3).joined(separator: "\n"), items)
        }
    }

    func deleteUnavailable() {
        let list = unavailable
        run("Padam peranti tak tersedia") {
            let before = list.reduce(Int64(0)) { $0 + ($1.size ?? 0) }
            let r = SimScan.ctl(["delete", "unavailable"])
            if r.status != 0 { return (0, 0, r.out.trimmingCharacters(in: .whitespacesAndNewlines), []) }
            return (before, list.count, nil, list.map { HistoryItem(name: $0.name, category: "Simulator", how: "Peranti tak tersedia dipadam", size: $0.size ?? 0) })
        }
    }

    func shutdownAll() {
        guard !busy else { return }
        busy = true
        Task.detached {
            _ = SimScan.ctl(["shutdown", "all"], timeout: 60)
            await MainActor.run {
                self.busy = false
                self.message = "Semua simulator dimatikan."
                self.refresh()
            }
        }
    }

    func deleteRuntime(_ r: SimRuntime) {
        run("Padam runtime \(r.name)") {
            let out = SimScan.ctl(["runtime", "delete", r.id], timeout: 180)
            if out.status != 0 { return (0, 0, "\(r.name): \(out.out.trimmingCharacters(in: .whitespacesAndNewlines))", []) }
            return (r.size, 1, nil, [HistoryItem(name: r.name, category: "Simulator", how: "Runtime dipadam", size: r.size)])
        }
    }
}
