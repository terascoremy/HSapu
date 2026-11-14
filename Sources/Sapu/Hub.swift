import AppKit
import SwiftUI

// MARK: models

struct WorktreeInfo: Identifiable, Codable {
    var id: String { path }
    let repoName: String
    let repoPath: String
    let path: String
    let name: String
    var branch: String
    var valid: Bool
    var dirty: Int
    var unpushed: Int
    var merged: Bool
    var lastCommit: Date?
    var size: Int64?

    var needsAttention: Bool { !valid || dirty > 0 || unpushed > 0 }
    var removable: Bool { valid && dirty == 0 && unpushed == 0 }
    var safeToRemove: Bool { removable && merged }
}

struct CIStatus: Codable {
    let state: String
    let title: String
    let when: Date?
}

struct BuildApp: Identifiable, Codable {
    var id: String { dir }
    let name: String
    let dir: String
    let repoName: String
    let repoPath: String
    let kind: String
    var version: String?
    var iosBuild: String?
    var androidCode: String?
    var bundleId: String?
    var branch: String = ""
    var lastCommit: Date?
    var remoteURL: String?
    var ci: CIStatus?
}

struct RunnerInfo: Identifiable {
    var id: String { dir }
    let name: String
    let dir: String
    let repo: String
    var running: Bool
    var busy: Bool
}

struct DockerInfo {
    var installed = false
    var running = false
    var total = 0
    var up = 0
}

// MARK: scans

enum HubScan {
    static let home = Scanner.home
    static let fm = FileManager.default
    static let git = Scanner.git

    static func rx(_ text: String, _ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]),
              let m = re.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)),
              m.numberOfRanges > 1, m.range(at: 1).location != NSNotFound else { return nil }
        return (text as NSString).substring(with: m.range(at: 1))
    }

    static func read(_ path: String) -> String? { try? String(contentsOfFile: path, encoding: .utf8) }

    // worktrees

    static func worktrees() -> [WorktreeInfo] {
        var repos = [String]()
        for c in Scanner.children(home) where !c.hasPrefix(".") && !Scanner.skipTop.contains(c) {
            let repo = home + "/" + c
            if Scanner.isDir(repo + "/.git") { repos.append(repo) }
        }
        var entries = [(repo: String, path: String)]()
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: repos.count) { i in
            let repo = repos[i]
            var found = [String]()
            let out = Shell.run(git, ["-C", repo, "worktree", "list", "--porcelain"]).out
            let listed = out.split(separator: "\n").filter { $0.hasPrefix("worktree ") }.map { String($0.dropFirst(9)) }
            for p in listed.dropFirst() where Scanner.isDir(p) { found.append(p) }
            let claude = repo + "/.claude/worktrees"
            for w in Scanner.children(claude) where !w.hasPrefix(".") {
                let p = claude + "/" + w
                if Scanner.isDir(p), !found.contains(p) { found.append(p) }
            }
            lock.lock()
            for p in found { entries.append((repo, p)) }
            lock.unlock()
        }
        guard !entries.isEmpty else { return [] }
        var mainOf = [String: String]()
        for repo in Set(entries.map { $0.repo }) {
            for cand in ["main", "master"] where Shell.run(git, ["-C", repo, "rev-parse", "--verify", "--quiet", cand]).status == 0 {
                mainOf[repo] = cand
                break
            }
        }
        var result = [WorktreeInfo]()
        DispatchQueue.concurrentPerform(iterations: entries.count) { i in
            let e = entries[i]
            let b = Shell.run(git, ["-C", e.path, "rev-parse", "--abbrev-ref", "HEAD"])
            let valid = b.status == 0 && fm.fileExists(atPath: e.path + "/.git")
            let branch = b.out.trimmingCharacters(in: .whitespacesAndNewlines)
            let dirty = Shell.run(git, ["-C", e.path, "status", "--porcelain"]).out.split(separator: "\n").count
            var merged = false
            if valid, let m = mainOf[e.repo] {
                merged = Shell.run(git, ["-C", e.path, "merge-base", "--is-ancestor", "HEAD", m]).status == 0
            }
            var unpushed = 0
            if valid, !merged {
                let up = Shell.run(git, ["-C", e.path, "rev-list", "--count", "@{u}..HEAD"])
                if up.status == 0 { unpushed = Int(up.out.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0 }
            }
            var date: Date?
            if valid {
                let t = Shell.run(git, ["-C", e.path, "log", "-1", "--format=%ct"]).out.trimmingCharacters(in: .whitespacesAndNewlines)
                if let n = TimeInterval(t) { date = Date(timeIntervalSince1970: n) }
            }
            let info = WorktreeInfo(repoName: (e.repo as NSString).lastPathComponent, repoPath: e.repo, path: e.path,
                                    name: (e.path as NSString).lastPathComponent,
                                    branch: branch == "HEAD" ? "detached" : branch, valid: valid, dirty: dirty,
                                    unpushed: unpushed, merged: merged, lastCommit: date, size: nil)
            lock.lock()
            result.append(info)
            lock.unlock()
        }
        return result
    }

    // apps

    static let skipDirs: Set<String> = ["node_modules", "Pods", "ios", "android", "build", "vendor", ".claude", "DerivedData", "dist", ".expo"]

    static func apps() -> [BuildApp] {
        var out = [BuildApp]()
        for c in Scanner.children(home).sorted() where !c.hasPrefix(".") && !Scanner.skipTop.contains(c) {
            let repo = home + "/" + c
            guard Scanner.isDir(repo + "/.git") else { continue }
            var handled = [String]()
            func walk(_ dir: String, _ depth: Int) {
                var made: BuildApp?
                let names = Scanner.children(dir)
                if names.contains("app.json"), let a = expoJSON(dir, repo) { made = a }
                else if names.contains("app.config.ts"), let a = expoTS(dir, repo) { made = a }
                else if names.contains("app.config.js"), let a = expoTS(dir, repo, file: "app.config.js") { made = a }
                else if names.contains("pubspec.yaml"), let a = flutter(dir, repo) { made = a }
                if let made {
                    out.append(made)
                    handled.append(dir)
                    return
                }
                guard depth < 3 else { return }
                for n in names where !n.hasPrefix(".") && !skipDirs.contains(n) {
                    let p = dir + "/" + n
                    if Scanner.isDir(p) { walk(p, depth + 1) }
                }
            }
            walk(repo, 0)
            func nativeWalk(_ dir: String, _ depth: Int) {
                if handled.contains(where: { dir == $0 || dir.hasPrefix($0 + "/") }) { return }
                for n in Scanner.children(dir) {
                    if n.hasSuffix(".xcodeproj"), !n.contains("Pods") {
                        if let a = native(dir + "/" + n, repo) { out.append(a) }
                        return
                    }
                }
                guard depth < 3 else { return }
                for n in Scanner.children(dir) where !n.hasPrefix(".") && n != "node_modules" && n != "Pods" && n != ".claude" && n != "build" {
                    let p = dir + "/" + n
                    if Scanner.isDir(p) { nativeWalk(p, depth + 1) }
                }
            }
            nativeWalk(repo, 0)
        }
        // git info
        for i in out.indices {
            let r = out[i].repoPath
            out[i].branch = Shell.run(git, ["-C", r, "rev-parse", "--abbrev-ref", "HEAD"]).out.trimmingCharacters(in: .whitespacesAndNewlines)
            let t = Shell.run(git, ["-C", out[i].dir, "log", "-1", "--format=%ct", "--", "."]).out.trimmingCharacters(in: .whitespacesAndNewlines)
            if let n = TimeInterval(t) { out[i].lastCommit = Date(timeIntervalSince1970: n) }
            var url = Shell.run(git, ["-C", r, "config", "--get", "remote.origin.url"]).out.trimmingCharacters(in: .whitespacesAndNewlines)
            if url.hasPrefix("git@github.com:") { url = "https://github.com/" + url.dropFirst("git@github.com:".count) }
            if url.hasSuffix(".git") { url = String(url.dropLast(4)) }
            out[i].remoteURL = url.hasPrefix("http") ? url : nil
        }
        return out
    }

    static func expoJSON(_ dir: String, _ repo: String) -> BuildApp? {
        guard let data = fm.contents(atPath: dir + "/app.json"),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let e = (root["expo"] as? [String: Any]) ?? root
        guard e["ios"] != nil || e["android"] != nil || e["name"] != nil else { return nil }
        let ios = e["ios"] as? [String: Any]
        let android = e["android"] as? [String: Any]
        var a = BuildApp(name: (e["name"] as? String) ?? (dir as NSString).lastPathComponent, dir: dir,
                         repoName: (repo as NSString).lastPathComponent, repoPath: repo, kind: "Expo")
        a.version = e["version"] as? String
        a.iosBuild = ios?["buildNumber"] as? String
        if let n = android?["versionCode"] as? Int { a.androidCode = String(n) }
        a.bundleId = (ios?["bundleIdentifier"] as? String) ?? (android?["package"] as? String)
        return a
    }

    static func expoTS(_ dir: String, _ repo: String, file: String = "app.config.ts") -> BuildApp? {
        guard let t = read(dir + "/" + file) else { return nil }
        var a = BuildApp(name: rx(t, #"^\s*name:\s*['"]([^'"]+)['"]"#) ?? (dir as NSString).lastPathComponent, dir: dir,
                         repoName: (repo as NSString).lastPathComponent, repoPath: repo, kind: "Expo")
        a.version = rx(t, #"^\s*version:\s*['"]([^'"]+)['"]"#)
        a.iosBuild = rx(t, #"buildNumber:\s*['"]?(\d+)"#)
        a.androidCode = rx(t, #"versionCode:\s*(\d+)"#)
        a.bundleId = rx(t, #"bundleIdentifier:\s*['"]([^'"]+)['"]"#) ?? rx(t, #"package:\s*['"]([^'"]+)['"]"#)
        return a
    }

    static func flutter(_ dir: String, _ repo: String) -> BuildApp? {
        guard let t = read(dir + "/pubspec.yaml"), rx(t, #"^(flutter):"#) != nil || t.contains("sdk: flutter") else { return nil }
        let name = rx(t, #"^name:\s*(\S+)"#) ?? (dir as NSString).lastPathComponent
        var a = BuildApp(name: name, dir: dir, repoName: (repo as NSString).lastPathComponent, repoPath: repo, kind: "Flutter")
        if let v = rx(t, #"^version:\s*(\S+)"#) {
            let parts = v.split(separator: "+", maxSplits: 1).map(String.init)
            a.version = parts.first
            if parts.count > 1 { a.iosBuild = parts[1]; a.androidCode = parts[1] }
        }
        if let gradle = read(dir + "/android/app/build.gradle.kts") ?? read(dir + "/android/app/build.gradle") {
            a.bundleId = rx(gradle, #"applicationId\s*=?\s*"([^"]+)""#)
        }
        return a
    }

    static func native(_ proj: String, _ repo: String) -> BuildApp? {
        guard let t = read(proj + "/project.pbxproj") else { return nil }
        func values(_ key: String) -> [String] {
            guard let re = try? NSRegularExpression(pattern: key + #"\s*=\s*"?([^";]+)"?;"#) else { return [] }
            let ns = t as NSString
            return re.matches(in: t, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
        }
        func common(_ v: [String]) -> String? {
            Dictionary(grouping: v, by: { $0 }).max { $0.value.count < $1.value.count }?.key
        }
        let ids = values("PRODUCT_BUNDLE_IDENTIFIER").filter { id in
            let l = id.lowercased()
            return !l.contains("tests") && !l.contains("widget") && !l.contains("extension")
        }
        let build = values("CURRENT_PROJECT_VERSION").compactMap { Int($0) }.max()
        let name = ((proj as NSString).lastPathComponent as NSString).deletingPathExtension
        var a = BuildApp(name: name, dir: (proj as NSString).deletingLastPathComponent, repoName: (repo as NSString).lastPathComponent,
                         repoPath: repo, kind: "iOS asli")
        a.version = common(values("MARKETING_VERSION"))
        a.iosBuild = build.map(String.init)
        a.bundleId = ids.min { $0.count < $1.count }
        return a
    }

    static func ci(for repo: String) -> CIStatus? {
        let gh = "/opt/homebrew/bin/gh"
        guard fm.fileExists(atPath: gh) else { return nil }
        let r = Shell.run(gh, ["run", "list", "--limit", "1", "--json", "status,conclusion,displayTitle,createdAt"], cwd: repo, timeout: 25)
        guard r.status == 0, let data = r.out.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], let first = arr.first else { return nil }
        let status = first["status"] as? String ?? ""
        let conclusion = first["conclusion"] as? String ?? ""
        let state = status == "completed" ? (conclusion.isEmpty ? "unknown" : conclusion) : status
        var when: Date?
        if let s = first["createdAt"] as? String { when = ISO8601DateFormatter().date(from: s) }
        return CIStatus(state: state, title: first["displayTitle"] as? String ?? "", when: when)
    }

    // runners

    static func runners() -> [RunnerInfo] {
        var dirs = [String]()
        for c in Scanner.children(home) where c.hasPrefix("actions-runner") {
            let base = home + "/" + c
            if fm.fileExists(atPath: base + "/.runner") { dirs.append(base) }
            for s in Scanner.children(base) where fm.fileExists(atPath: base + "/" + s + "/.runner") { dirs.append(base + "/" + s) }
        }
        let ps = Shell.run("/bin/ps", ["-axo", "command="]).out
        var out = [RunnerInfo]()
        for d in dirs.sorted() {
            var text = read(d + "/.runner") ?? ""
            text = text.replacingOccurrences(of: "\u{FEFF}", with: "")
            var name = (d as NSString).lastPathComponent
            var repo = ""
            if let data = text.data(using: .utf8), let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                name = (j["agentName"] as? String) ?? name
                if let u = j["gitHubUrl"] as? String { repo = u.split(separator: "/").suffix(2).joined(separator: "/") }
            }
            let running = ps.contains(d + "/bin/Runner.Listener")
            let busy = ps.contains(d + "/bin/Runner.Worker")
            out.append(RunnerInfo(name: name, dir: d, repo: repo, running: running, busy: busy))
        }
        return out
    }

    static func startRunner(_ dir: String, name: String) {
        let logPath = home + "/Library/Logs/Sapu-runner-\(name).log"
        if !fm.fileExists(atPath: logPath) { fm.createFile(atPath: logPath, contents: nil) }
        guard let log = FileHandle(forWritingAtPath: logPath) else { return }
        log.seekToEndOfFile()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        // setsid supaya runner terus hidup walaupun Sapu ditutup
        p.arguments = ["-MPOSIX", "-e", "POSIX::setsid(); exec @ARGV", "./run.sh"]
        p.currentDirectoryURL = URL(fileURLWithPath: dir)
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = log
        p.standardError = log
        try? p.run()
        try? log.close()
    }

    static func stopRunner(_ dir: String) {
        _ = Shell.run("/usr/bin/pkill", ["-TERM", "-f", dir + "/bin/Runner.Listener"])
    }

    // docker, simulators

    static func docker() -> DockerInfo {
        var info = DockerInfo()
        let candidates = ["/usr/local/bin/docker", "/opt/homebrew/bin/docker", "/Applications/Docker.app/Contents/Resources/bin/docker"]
        guard let bin = candidates.first(where: { fm.fileExists(atPath: $0) }) else { return info }
        info.installed = true
        let r = Shell.run(bin, ["ps", "-a", "--format", "{{.Status}}"], timeout: 6)
        guard r.status == 0 else { return info }
        info.running = true
        let lines = r.out.split(separator: "\n")
        info.total = lines.count
        info.up = lines.filter { $0.hasPrefix("Up") }.count
        return info
    }

    static func bootedSims() -> Int {
        let r = Shell.run("/usr/bin/xcrun", ["simctl", "list", "devices", "booted"], timeout: 10)
        return r.out.split(separator: "\n").filter { $0.contains("(Booted)") }.count
    }

    static func avds() -> [String] {
        Scanner.children(home + "/.android/avd").filter { $0.hasSuffix(".avd") }.map { String($0.dropLast(4)) }.sorted()
    }

    static func emulatorsRunning() -> Int {
        let ps = Shell.run("/bin/ps", ["-axo", "command="]).out
        return ps.split(separator: "\n").filter { $0.contains("qemu-system") && $0.contains("-avd") }.count
    }
}

// MARK: state

@MainActor
final class HubState: ObservableObject {
    @Published var worktrees: [WorktreeInfo] = []
    @Published var loadingWT = false
    @Published var apps: [BuildApp] = []
    @Published var loadingApps = false
    @Published var runners: [RunnerInfo] = []
    @Published var docker = DockerInfo()
    @Published var bootedSims = 0
    @Published var avds: [String] = []
    @Published var emulators = 0
    @Published var message: String?
    @Published var busy = false
    @Published var checklists: [String: [Bool]] = [:]

    static let checklistItems = [
        "Naikkan nombor build atau versionCode",
        "Build di CI lulus",
        "Diuji pada peranti sebenar",
        "Nota keluaran siap",
        "Dihantar ke TestFlight atau Play Console",
    ]

    private var timer: Timer?

    init() {
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("sapu.checklist.") {
            if let v = UserDefaults.standard.array(forKey: key) as? [Bool] {
                checklists[String(key.dropFirst("sapu.checklist.".count))] = v
            }
        }
        if let snap = Store.load(HubSnapshot.self, "hub-cache.json") {
            let fm = FileManager.default
            worktrees = snap.worktrees.filter { fm.fileExists(atPath: $0.path) }
            apps = snap.apps
        }
        timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshLive() }
        }
    }

    var attentionCount: Int { worktrees.filter { $0.needsAttention }.count }
    var safeWorktrees: [WorktreeInfo] { worktrees.filter { $0.safeToRemove && !Exclusions.isExcluded($0.path) } }

    func exclude(_ w: WorktreeInfo) {
        Exclusions.add(w.path)
        objectWillChange.send()
    }

    func saveCache() {
        Store.save(HubSnapshot(date: Date(), worktrees: worktrees, apps: apps), "hub-cache.json")
    }
    var runnersUp: Int { runners.filter { $0.running }.count }

    func refreshAll() {
        loadWorktrees()
        loadApps()
        refreshLive()
    }

    func loadWorktrees() {
        guard !loadingWT else { return }
        loadingWT = true
        let known = Dictionary(worktrees.compactMap { w in w.size.map { (w.path, $0) } }, uniquingKeysWith: { a, _ in a })
        Task.detached(priority: .userInitiated) {
            var list = HubScan.worktrees()
            // Papar saiz lama serta-merta (walaupun lapuk) supaya tak perlu tunggu `du`.
            let old = SizeCache.any(list.map { $0.path })
            for i in list.indices { list[i].size = known[list[i].path] ?? old[list[i].path] }
            let shown = list
            await MainActor.run {
                self.worktrees = shown
                self.loadingWT = false
            }
            let sizes = Scanner.cachedSizes(list.map { $0.path })
            await MainActor.run {
                for i in self.worktrees.indices { self.worktrees[i].size = sizes[self.worktrees[i].path] ?? self.worktrees[i].size }
                self.saveCache()
            }
        }
    }

    func loadApps() {
        guard !loadingApps else { return }
        loadingApps = true
        Task.detached(priority: .userInitiated) {
            let list = HubScan.apps()
            await MainActor.run {
                self.apps = list
                self.loadingApps = false
            }
            let repos = Array(Set(list.map { $0.repoPath }))
            var status = [String: CIStatus]()
            let lock = NSLock()
            DispatchQueue.concurrentPerform(iterations: repos.count) { i in
                if let s = HubScan.ci(for: repos[i]) {
                    lock.lock()
                    status[repos[i]] = s
                    lock.unlock()
                }
            }
            let finalStatus = status
            await MainActor.run {
                for i in self.apps.indices { self.apps[i].ci = finalStatus[self.apps[i].repoPath] }
                self.saveCache()
            }
        }
    }

    func refreshLive() {
        Task.detached(priority: .utility) {
            let r = HubScan.runners()
            let d = HubScan.docker()
            let s = HubScan.bootedSims()
            let a = HubScan.avds()
            let e = HubScan.emulatorsRunning()
            await MainActor.run {
                self.runners = r
                self.docker = d
                self.bootedSims = s
                self.avds = a
                self.emulators = e
            }
        }
    }

    func start(_ r: RunnerInfo) {
        Task.detached {
            HubScan.startRunner(r.dir, name: r.name)
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run { self.refreshLive() }
        }
    }

    func stop(_ r: RunnerInfo) {
        Task.detached {
            HubScan.stopRunner(r.dir)
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run { self.refreshLive() }
        }
    }

    func shutdownSims() {
        Task.detached {
            _ = Shell.run("/usr/bin/xcrun", ["simctl", "shutdown", "all"], timeout: 30)
            await MainActor.run { self.refreshLive() }
        }
    }

    func openDocker() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Docker.app"))
    }

    func remove(_ list: [WorktreeInfo]) {
        guard !busy, !list.isEmpty else { return }
        busy = true
        message = nil
        Task.detached {
            var done = [String]()
            var errors = [String]()
            for w in list {
                let item = CleanItem(name: w.name, path: w.path, detail: "", size: 0, safety: .safe, action: .worktree(repo: w.repoPath), selected: true)
                if let e = Cleaner.perform(item) { errors.append(e) } else { done.append(w.path) }
            }
            let freed = list.filter { done.contains($0.path) }.reduce(Int64(0)) { $0 + ($1.size ?? 0) }
            let recorded = list.filter { done.contains($0.path) }.map {
                HistoryItem(name: "\($0.repoName)/\($0.name)", category: "Worktree git", how: "Worktree dibuang, branch kekal", size: $0.size ?? 0)
            }
            History.record(freed: freed, count: done.count, note: "Worktree", items: recorded)
            let removed = done, failures = errors
            await MainActor.run {
                self.worktrees.removeAll { removed.contains($0.path) }
                self.saveCache()
                self.busy = false
                self.message = failures.isEmpty ? "\(removed.count) worktree dibuang. Branch kekal." : failures.prefix(3).joined(separator: "\n")
            }
        }
    }

    func toggleCheck(_ app: BuildApp, _ i: Int) {
        var v = checklists[app.id] ?? Array(repeating: false, count: Self.checklistItems.count)
        v[i].toggle()
        checklists[app.id] = v
        UserDefaults.standard.set(v, forKey: "sapu.checklist." + app.id)
    }

    func resetChecks(_ app: BuildApp) {
        checklists[app.id] = nil
        UserDefaults.standard.removeObject(forKey: "sapu.checklist." + app.id)
    }
}

// MARK: helpers

func ago(_ d: Date?) -> String {
    guard let d else { return "tarikh tak diketahui" }
    if abs(d.timeIntervalSinceNow) < 60 { return "baru sebentar tadi" }
    let f = RelativeDateTimeFormatter()
    f.locale = Locale(identifier: "ms_MY")
    f.unitsStyle = .short
    return f.localizedString(for: d, relativeTo: Date())
}

enum Opener {
    static func terminal(_ path: String) {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
        NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    static func editorURL() -> URL? {
        for id in ["com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "com.apple.dt.Xcode"] {
            if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { return u }
        }
        return nil
    }

    static func editor(_ path: String) {
        guard let app = editorURL() else { return }
        NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    static func finder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    static func url(_ s: String) {
        if let u = URL(string: s) { NSWorkspace.shared.open(u) }
    }
}
