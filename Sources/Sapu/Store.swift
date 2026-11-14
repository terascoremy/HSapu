import AppKit
import Foundation
import ServiceManagement
import UserNotifications

// MARK: storage

enum AppSupport {
    /// Diganti semasa ujian supaya data sebenar tak disentuh.
    static var override: String?

    static var dir: String {
        let d = override ?? (NSHomeDirectory() + "/Library/Application Support/Sapu")
        try? FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        return d
    }
}

enum Store {
    static let enc: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    static let dec: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let d = FileManager.default.contents(atPath: AppSupport.dir + "/" + name) else { return nil }
        return try? dec.decode(T.self, from: d)
    }

    static func save<T: Encodable>(_ value: T, _ name: String) {
        guard let d = try? enc.encode(value) else { return }
        try? d.write(to: URL(fileURLWithPath: AppSupport.dir + "/" + name), options: .atomic)
    }
}

// MARK: preferences

enum Prefs {
    static var defaults = UserDefaults.standard

    private static func bool(_ key: String, _ def: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? def }
    private static func int(_ key: String, _ def: Int) -> Int { defaults.object(forKey: key) as? Int ?? def }
    private static func date(_ key: String) -> Date? { defaults.object(forKey: key) as? Date }

    static var lowDiskAlert: Bool {
        get { bool("sapu.lowDiskAlert", false) }
        set { defaults.set(newValue, forKey: "sapu.lowDiskAlert") }
    }
    static var lowDiskGB: Int {
        get { int("sapu.lowDiskGB", 50) }
        set { defaults.set(newValue, forKey: "sapu.lowDiskGB") }
    }
    /// 0 = mati, selain itu bilangan hari antara imbasan automatik.
    static var scanEveryDays: Int {
        get { int("sapu.scanEveryDays", 0) }
        set { defaults.set(newValue, forKey: "sapu.scanEveryDays") }
    }
    static var checkUpdates: Bool {
        get { bool("sapu.checkUpdates", true) }
        set { defaults.set(newValue, forKey: "sapu.checkUpdates") }
    }
    static var trashFirst: Bool {
        get { bool("sapu.trashFirst", false) }
        set { defaults.set(newValue, forKey: "sapu.trashFirst") }
    }
    static var lastLowDiskNotice: Date? {
        get { date("sapu.lastLowDiskNotice") }
        set { defaults.set(newValue, forKey: "sapu.lastLowDiskNotice") }
    }
    static var lastAutoScan: Date? {
        get { date("sapu.lastAutoScan") }
        set { defaults.set(newValue, forKey: "sapu.lastAutoScan") }
    }
    static var lastUpdateCheck: Date? {
        get { date("sapu.lastUpdateCheck") }
        set { defaults.set(newValue, forKey: "sapu.lastUpdateCheck") }
    }
}

// MARK: exclusions (senarai jangan sentuh)

enum Exclusions {
    static let key = "sapu.exclusions"

    static var list: [String] { Prefs.defaults.stringArray(forKey: key) ?? [] }

    static func add(_ path: String) {
        var l = list
        if !l.contains(path) { l.append(path) }
        Prefs.defaults.set(l, forKey: key)
    }

    static func remove(_ path: String) {
        Prefs.defaults.set(list.filter { $0 != path }, forKey: key)
    }

    /// Dikecualikan jika laluan sama, di dalam folder dikecualikan, atau mengandungi folder dikecualikan.
    static func isExcluded(_ path: String) -> Bool {
        list.contains { path == $0 || path.hasPrefix($0 + "/") || $0.hasPrefix(path + "/") }
    }

    static func filter(_ items: [CleanItem]) -> [CleanItem] {
        let l = list
        if l.isEmpty { return items }
        return items.filter { !isExcluded($0.path) }
    }
}

// MARK: cache imbasan

struct ScanSnapshot: Codable {
    var date: Date
    var items: [String: [CleanItem]]
}

struct HubSnapshot: Codable {
    var date: Date
    var worktrees: [WorktreeInfo]
    var apps: [BuildApp]
}

enum SizeCache {
    struct Entry: Codable {
        var size: Int64
        var at: Date
    }

    private static let lock = NSLock()
    private static var map: [String: Entry]?
    private static let file = "size-cache.json"

    private static func ensure() -> [String: Entry] {
        if let m = map { return m }
        let m = Store.load([String: Entry].self, file) ?? [:]
        map = m
        return m
    }

    static func reset() {
        lock.lock()
        map = nil
        lock.unlock()
    }

    /// Saiz yang masih segar sahaja.
    static func fresh(_ paths: [String], maxAge: TimeInterval) -> [String: Int64] {
        lock.lock()
        defer { lock.unlock() }
        let m = ensure()
        let now = Date()
        var out = [String: Int64]()
        for p in paths { if let e = m[p], now.timeIntervalSince(e.at) <= maxAge { out[p] = e.size } }
        return out
    }

    /// Apa-apa saiz yang pernah dikira, walaupun lapuk. Untuk paparan segera.
    static func any(_ paths: [String]) -> [String: Int64] {
        lock.lock()
        defer { lock.unlock() }
        let m = ensure()
        var out = [String: Int64]()
        for p in paths { if let e = m[p] { out[p] = e.size } }
        return out
    }

    static func put(_ sizes: [String: Int64]) {
        lock.lock()
        var m = ensure()
        let now = Date()
        for (p, s) in sizes { m[p] = Entry(size: s, at: now) }
        // Buang entri lebih 14 hari supaya fail tak membengkak.
        m = m.filter { now.timeIntervalSince($0.value.at) < 14 * 86400 }
        map = m
        let snapshot = m
        lock.unlock()
        Store.save(snapshot, file)
    }
}

// MARK: sejarah pembersihan

struct HistoryEntry: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var freed: Int64
    var count: Int
    var note: String
}

enum History {
    private static let file = "history.json"

    static func all() -> [HistoryEntry] {
        // Tarikh disimpan hingga saat; guna kedudukan untuk menentukan yang terbaru bila sama saat.
        (Store.load([HistoryEntry].self, file) ?? []).enumerated()
            .sorted { ($0.element.date, $0.offset) > ($1.element.date, $1.offset) }
            .map { $0.element }
    }

    static func record(freed: Int64, count: Int, note: String) {
        guard count > 0 else { return }
        var list = Store.load([HistoryEntry].self, file) ?? []
        list.append(HistoryEntry(date: Date(), freed: freed, count: count, note: note))
        Store.save(list, file)
    }

    static var totalFreed: Int64 { all().reduce(0) { $0 + $1.freed } }
}

// MARK: notifikasi, log masuk, akses cakera

enum Notifier {
    /// Notifikasi hanya berfungsi untuk .app sebenar, bukan binari terus.
    static var available: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app") }

    static func requestAuth(_ done: @escaping (Bool) -> Void) {
        guard available else { done(false); return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { ok, _ in
            DispatchQueue.main.async { done(ok) }
        }
    }

    static func send(_ title: String, _ body: String) {
        guard available else { return }
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
}

enum LoginItem {
    static var enabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

enum Access {
    /// nil = tak dapat ditentukan, true = ada Akses Cakera Penuh, false = tiada.
    static func fullDisk() -> Bool? {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        var tested = false
        for p in [home + "/Library/Safari", home + "/Library/Mail", home + "/Library/Messages"] where fm.fileExists(atPath: p) {
            tested = true
            if (try? fm.contentsOfDirectory(atPath: p)) != nil { return true }
        }
        return tested ? false : nil
    }

    static func openSettings() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(u)
        }
    }
}
