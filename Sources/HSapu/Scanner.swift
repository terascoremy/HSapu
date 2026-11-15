import Foundation

enum Shell {
    static func run(_ exe: String, _ args: [String], mergeErr: Bool = false, cwd: String? = nil, timeout: Double = 0) -> (status: Int32, out: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = mergeErr ? pipe : FileHandle.nullDevice
        do { try p.run() } catch { return (-1, "") }
        if timeout > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { if p.isRunning { p.terminate() } }
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}

enum Scanner {
    static let ids = ["system", "xcode", "dev", "node", "worktree", "home", "downloads", "big"]
    static let home = NSHomeDirectory()
    static let fm = FileManager.default
    static let MB: Int64 = 1024 * 1024

    static func scan(_ id: String) -> [CleanItem] {
        var items: [CleanItem]
        switch id {
        case "system": items = system()
        case "xcode": items = xcode()
        case "dev": items = dev()
        case "node": items = nodeModules()
        case "worktree": items = worktrees()
        case "home": items = homeFolders()
        case "downloads": items = downloads()
        case "big": items = bigFiles()
        default: items = []
        }
        items = ItemMeta.enrich(items)
        if id == "worktree" || id == "downloads" || id == "home" {
            return items.sorted { ($0.safety.rawValue, -$0.size) < ($1.safety.rawValue, -$1.size) }
        }
        return items.sorted { $0.size > $1.size }
    }

    // MARK: helpers

    static func exists(_ path: String) -> Bool { fm.fileExists(atPath: path) }

    static func isDir(_ path: String) -> Bool {
        var d: ObjCBool = false
        return fm.fileExists(atPath: path, isDirectory: &d) && d.boolValue
    }

    static func children(_ path: String) -> [String] {
        (try? fm.contentsOfDirectory(atPath: path)) ?? []
    }

    static func short(_ path: String) -> String {
        path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    static func sizes(_ paths: [String]) -> [String: Int64] {
        guard !paths.isEmpty else { return [:] }
        let lock = NSLock()
        var result = [String: Int64]()
        DispatchQueue.concurrentPerform(iterations: paths.count) { i in
            let (_, out) = Shell.run("/usr/bin/du", ["-sk", paths[i]])
            if let first = out.split(separator: "\t").first,
               let kb = Int64(first.trimmingCharacters(in: .whitespacesAndNewlines)) {
                lock.lock()
                result[paths[i]] = kb * 1024
                lock.unlock()
            }
        }
        return result
    }

    static func size(_ path: String) -> Int64 { sizes([path])[path] ?? 0 }

    /// Umur maksimum saiz dicache untuk folder besar (Xcode, dev, node_modules, folder home).
    /// Imbasan di latar guna lebih lama; imbasan manual lebih pendek.
    static var sizeMaxAge: TimeInterval = 3 * 3600

    static func fastSizes(_ paths: [String]) -> [String: Int64] { cachedSizes(paths, maxAge: sizeMaxAge) }

    /// Guna saiz yang dikira dalam `maxAge` terakhir, kira hanya yang belum ada atau lapuk.
    static func cachedSizes(_ paths: [String], maxAge: TimeInterval = 6 * 3600) -> [String: Int64] {
        var result = SizeCache.fresh(paths, maxAge: maxAge)
        let missing = paths.filter { result[$0] == nil }
        if !missing.isEmpty {
            let fresh = sizes(missing)
            SizeCache.put(fresh)
            for (k, v) in fresh { result[k] = v }
        }
        return result
    }

    // MARK: system

    static func system() -> [CleanItem] {
        var items = [CleanItem]()
        let caches = home + "/Library/Caches"
        let paths = children(caches)
            .filter { !$0.hasPrefix("com.apple.") && !$0.hasPrefix(".") && $0 != "familycircled" && $0 != "CloudKit" }
            .map { caches + "/" + $0 }
        let sz = sizes(paths)
        for p in paths {
            let s = sz[p] ?? 0
            if s >= 20 * MB {
                items.append(CleanItem(name: (p as NSString).lastPathComponent, path: p, detail: "Cache aplikasi, dibina semula bila perlu",
                                       size: s, safety: .safe, action: .delete, selected: true))
            }
        }
        let logs = home + "/Library/Logs"
        let ls = size(logs)
        if ls >= 5 * MB {
            items.append(CleanItem(name: "Log aplikasi", path: logs, detail: short(logs), size: ls, safety: .safe, action: .deleteContents, selected: true))
        }
        let trash = home + "/.Trash"
        let ts = size(trash)
        if ts >= MB {
            items.append(CleanItem(name: "Tong Sampah", path: trash, detail: "Kosongkan terus", size: ts, safety: .safe, action: .deleteContents, selected: true))
        }
        return items
    }

    // MARK: xcode

    static func xcode() -> [CleanItem] {
        let dev = home + "/Library/Developer"
        let defs: [(String, String, String, Safety, CleanAction)] = [
            ("DerivedData", dev + "/Xcode/DerivedData", "Cache build, dibina semula pada build seterusnya", .safe, .deleteContents),
            ("iOS DeviceSupport", dev + "/Xcode/iOS DeviceSupport", "Simbol peranti, dimuat turun semula bila sambung", .safe, .deleteContents),
            ("Cache simulator", dev + "/CoreSimulator/Caches", "Cache dyld simulator", .safe, .deleteContents),
            ("Xcode Archives", dev + "/Xcode/Archives", "Mengandungi dSYM untuk crash report", .review, .deleteContents),
            ("Data semua simulator", dev + "/CoreSimulator/Devices", "App dan login dalam simulator hilang. Saiz ialah anggaran.", .review, .simulatorErase),
        ]
        let paths = defs.map { $0.1 }.filter { exists($0) }
        let sz = fastSizes(paths)
        var items = [CleanItem]()
        for d in defs {
            let s = sz[d.1] ?? 0
            if s >= 10 * MB {
                items.append(CleanItem(name: d.0, path: d.1, detail: d.2, size: s, safety: d.3, action: d.4, selected: d.3 == .safe))
            }
        }
        return items
    }

    // MARK: developer caches

    static func dev() -> [CleanItem] {
        var defs: [(String, String, String, Safety, CleanAction)] = [
            ("Gradle cache", home + "/.gradle/caches", "Dimuat turun semula pada build Android", .safe, .delete),
            ("npm cache", home + "/.npm/_cacache", "Cache pakej npm", .safe, .delete),
            ("Yarn cache", home + "/Library/Caches/Yarn", "Cache pakej Yarn", .safe, .delete),
            ("Dart pub cache", home + "/.pub-cache", "Pakej Flutter dan Dart", .review, .delete),
            ("Cargo registry", home + "/.cargo/registry", "Pakej Rust", .safe, .delete),
            ("CocoaPods repos", home + "/.cocoapods/repos", "Spec repo CocoaPods", .safe, .delete),
            ("Sesi Codex", home + "/.codex/sessions", "Sejarah sesi Codex lama", .review, .delete),
        ]
        let cache = home + "/.cache"
        for c in children(cache) where !c.hasPrefix(".") {
            defs.append((c, cache + "/" + c, "Cache dalam ~/.cache", .safe, .delete))
        }
        let avd = home + "/.android/avd"
        for c in children(avd) where c.hasSuffix(".avd") {
            defs.append(("Emulator " + String(c.dropLast(4)), avd + "/" + c, "Emulator Android, perlu dicipta semula", .review, .delete))
        }
        let paths = defs.map { $0.1 }.filter { exists($0) }
        let sz = fastSizes(paths)
        var items = [CleanItem]()
        for d in defs {
            let s = sz[d.1] ?? 0
            if s >= 20 * MB {
                items.append(CleanItem(name: d.0, path: d.1, detail: d.2, size: s, safety: d.3, action: d.4, selected: d.3 == .safe))
            }
        }
        return items
    }

    // MARK: node_modules

    static let skipTop: Set<String> = ["Library", "Applications", "Pictures", "Music", "Movies", "Desktop", "Documents", "Downloads", "Public"]

    static func nodeModules() -> [CleanItem] {
        var found = [String]()
        func walk(_ dir: String, _ depth: Int) {
            for c in children(dir) {
                if c.hasPrefix(".") { continue }
                let p = dir + "/" + c
                if depth == 0 && skipTop.contains(c) { continue }
                if c == "node_modules" {
                    if isDir(p) { found.append(p) }
                    continue
                }
                if depth < 3, isDir(p), (try? fm.destinationOfSymbolicLink(atPath: p)) == nil {
                    walk(p, depth + 1)
                }
            }
        }
        walk(home, 0)
        let sz = fastSizes(found)
        return found.compactMap { p in
            let s = sz[p] ?? 0
            guard s >= 50 * MB else { return nil }
            let project = (p as NSString).deletingLastPathComponent
            return CleanItem(name: short(project), path: p, detail: "Jalankan npm install untuk pasang semula",
                             size: s, safety: .review, action: .delete, selected: false)
        }
    }

    // MARK: Claude Code worktrees

    static let git = "/usr/bin/git"

    static func worktrees() -> [CleanItem] {
        var repos = [String]()
        for c in children(home) where !c.hasPrefix(".") && !skipTop.contains(c) {
            let repo = home + "/" + c
            if isDir(repo + "/.git") { repos.append(repo) }
        }
        var entries = [(repo: String, path: String)]()
        let entryLock = NSLock()
        DispatchQueue.concurrentPerform(iterations: repos.count) { i in
            let repo = repos[i]
            var found = [String]()
            let out = Shell.run(git, ["-C", repo, "worktree", "list", "--porcelain"]).out
            let listed = out.split(separator: "\n").filter { $0.hasPrefix("worktree ") }.map { String($0.dropFirst(9)) }
            for p in listed.dropFirst() where isDir(p) { found.append(p) }
            let claude = repo + "/.claude/worktrees"
            for w in children(claude) where !w.hasPrefix(".") {
                let p = claude + "/" + w
                if isDir(p), !found.contains(p) { found.append(p) }
            }
            entryLock.lock()
            for p in found { entries.append((repo, p)) }
            entryLock.unlock()
        }
        guard !entries.isEmpty else { return [] }
        var mainOf = [String: String]()
        for repo in Set(entries.map { $0.repo }) {
            for cand in ["main", "master"] {
                if Shell.run(git, ["-C", repo, "rev-parse", "--verify", "--quiet", cand]).status == 0 {
                    mainOf[repo] = cand
                    break
                }
            }
        }
        let sz = cachedSizes(entries.map { $0.path })
        let lock = NSLock()
        var items = [CleanItem]()
        DispatchQueue.concurrentPerform(iterations: entries.count) { i in
            let e = entries[i]
            let s = sz[e.path] ?? 0
            let branchOut = Shell.run(git, ["-C", e.path, "rev-parse", "--abbrev-ref", "HEAD"])
            let valid = branchOut.status == 0 && fm.fileExists(atPath: e.path + "/.git")
            let branch = branchOut.out.trimmingCharacters(in: .whitespacesAndNewlines)
            let dirty = Shell.run(git, ["-C", e.path, "status", "--porcelain"]).out.split(separator: "\n").count
            var merged = false
            if valid, let main = mainOf[e.repo] {
                merged = Shell.run(git, ["-C", e.path, "merge-base", "--is-ancestor", "HEAD", main]).status == 0
            }
            var unpushed = 0
            if valid, !merged {
                let up = Shell.run(git, ["-C", e.path, "rev-list", "--count", "@{u}..HEAD"])
                if up.status == 0 { unpushed = Int(up.out.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0 }
            }
            let repoName = (e.repo as NSString).lastPathComponent
            let safety: Safety
            var note: String
            if !valid {
                safety = .locked
                note = "Bukan worktree git yang sah"
            } else if dirty > 0 {
                safety = .locked
                note = "\(dirty) fail belum commit"
            } else if unpushed > 0 {
                safety = .locked
                note = "\(unpushed) commit belum push"
            } else if merged {
                safety = .safe
                note = "Dah merge, bersih"
            } else {
                safety = .review
                note = "Belum merge, bersih"
            }
            note = "\(repoName) · \(branch == "HEAD" ? "detached" : branch) · \(note)"
            let item = CleanItem(name: (e.path as NSString).lastPathComponent, path: e.path, detail: note,
                                 size: s, safety: safety, action: .worktree(repo: e.repo), selected: false)
            lock.lock()
            items.append(item)
            lock.unlock()
        }
        return items
    }

    // MARK: home folders

    static func homeFolders() -> [CleanItem] {
        let covered: Set<String> = [".Trash", ".gradle", ".npm", ".cache", ".pub-cache", ".cargo", ".cocoapods", ".android", ".claude", ".codex", ".DS_Store"]
        var top = [String]()
        for c in children(home) where !skipTop.contains(c) && !covered.contains(c) {
            let p = home + "/" + c
            if fm.fileExists(atPath: p + "/.git") && !isDir(p + "/.git") { continue }
            top.append(p)
        }
        let containers: [(String, Set<String>, String)] = [
            (".claude", ["projects"], "Data Claude Code"),
            (".claude/projects", [], "Sejarah sesi Claude Code untuk projek ini"),
            (".codex", ["sessions"], "Data Codex"),
        ]
        var inner = [(path: String, label: String, hint: String)]()
        for (dir, skip, hint) in containers {
            for c in children(home + "/" + dir) where !skip.contains(c) {
                inner.append((home + "/" + dir + "/" + c, dir + "/" + c, hint))
            }
        }
        let sz = fastSizes(top + inner.map { $0.path })
        let df = DateFormatter()
        df.locale = Lang.locale
        df.dateFormat = "d MMM yyyy"
        var items = [CleanItem]()

        for p in top {
            let s = sz[p] ?? 0
            guard s >= 100 * MB else { continue }
            let name = (p as NSString).lastPathComponent
            let lower = name.lowercased()
            let dir = isDir(p)
            if isDir(p + "/.git") {
                items.append(CleanItem(name: name, path: p, detail: "Projek git, tak disentuh. Lihat Worktree git dan node_modules untuk bahagian yang boleh dibuang.",
                                       size: s, safety: .locked, action: .trash, selected: false))
                continue
            }
            if dir, children(p).contains(where: { fm.fileExists(atPath: p + "/" + $0 + "/.git") && !isDir(p + "/" + $0 + "/.git") }) {
                items.append(CleanItem(name: name, path: p, detail: "Mengandungi git worktree. Buang melalui kategori Worktree git.",
                                       size: s, safety: .locked, action: .trash, selected: false))
                continue
            }
            if dir, lower.contains("backup") {
                let keys: [URLResourceKey] = [.contentModificationDateKey, .totalFileAllocatedSizeKey, .isRegularFileKey]
                let files = ((try? fm.contentsOfDirectory(at: URL(fileURLWithPath: p), includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? [])
                    .compactMap { u -> (String, Date, Int64)? in
                        guard let v = try? u.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { return nil }
                        return (u.path, v.contentModificationDate ?? .distantPast, Int64(v.totalFileAllocatedSize ?? 0))
                    }
                    .sorted { $0.1 > $1.1 }
                if files.count > 7 {
                    let old = Array(files.dropFirst(7))
                    let total = old.reduce(Int64(0)) { $0 + $1.2 }
                    items.append(CleanItem(name: "\(name): sandaran lama", path: p,
                                           detail: "\(old.count) fail lama, 7 terbaru dikekalkan · dialih ke Tong Sampah",
                                           size: total, safety: .review, action: .trashList(old.map { $0.0 }), selected: false))
                    continue
                }
            }
            var safety = Safety.review
            var hint: String
            if lower == ".dartserver" {
                safety = .safe
                hint = "Cache penganalisis Dart, dibina semula"
            } else if lower == ".expo" {
                hint = "Cache dan tetapan Expo"
            } else if lower.contains("venv") || fm.fileExists(atPath: p + "/pyvenv.cfg") {
                hint = "Persekitaran Python, boleh dicipta semula"
            } else if lower.hasPrefix("actions-runner") {
                hint = "Runner GitHub Actions. Jangan buang kalau CI masih guna"
            } else if name.hasPrefix(".") {
                hint = "Data alat \(name)"
            } else {
                let attrs = try? fm.attributesOfItem(atPath: p)
                let when = (attrs?[.modificationDate] as? Date).map { df.string(from: $0) } ?? "tarikh tak diketahui"
                hint = (dir ? "Folder" : "Fail") + " · diubah \(when)"
            }
            items.append(CleanItem(name: name, path: p, detail: hint + " · dialih ke Tong Sampah",
                                   size: s, safety: safety, action: .trash, selected: safety == .safe))
        }
        for i in inner {
            let s = sz[i.path] ?? 0
            guard s >= 200 * MB else { continue }
            var label = i.label
            if label.hasPrefix(".claude/projects/") {
                var proj = String(label.dropFirst(".claude/projects/".count))
                let prefix = home.replacingOccurrences(of: "/", with: "-") + "-"
                if proj.hasPrefix(prefix) { proj = String(proj.dropFirst(prefix.count)) }
                label = "Sesi Claude: " + proj.replacingOccurrences(of: "--claude-worktrees-", with: " › ")
            }
            items.append(CleanItem(name: label, path: i.path, detail: i.hint + " · dialih ke Tong Sampah",
                                   size: s, safety: .review, action: .trash, selected: false))
        }
        return items
    }

    // MARK: downloads

    static func originalName(of name: String) -> String? {
        for pattern in ["^(.+) \\((\\d+)\\)(\\.[^.]+)?$", "^(.+) copy( \\d+)?(\\.[^.]+)?$"] {
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = name as NSString
            if let m = re.firstMatch(in: name, range: NSRange(location: 0, length: ns.length)) {
                let base = ns.substring(with: m.range(at: 1))
                let ext = m.range(at: 3).location != NSNotFound ? ns.substring(with: m.range(at: 3)) : ""
                return base + ext
            }
        }
        return nil
    }

    static func downloads() -> [CleanItem] {
        let root = home + "/Downloads"
        let names = children(root).filter { !$0.hasPrefix(".") }
        var info = [(name: String, path: String, isDir: Bool, size: Int64, date: Date?)]()
        var dirs = [String]()
        for n in names {
            let p = root + "/" + n
            let attrs = try? fm.attributesOfItem(atPath: p)
            let d = (attrs?[.type] as? FileAttributeType) == .typeDirectory
            if d { dirs.append(p) }
            info.append((n, p, d, (attrs?[.size] as? NSNumber)?.int64Value ?? 0, attrs?[.modificationDate] as? Date))
        }
        let dsz = sizes(dirs)
        let dirNames = Set(info.filter { $0.isDir }.map { $0.name })
        var fileSize = [String: Int64]()
        for i in info where !i.isDir { fileSize[i.name] = i.size }

        let df = DateFormatter()
        df.locale = Lang.locale
        df.dateFormat = "d MMM yyyy"
        let installers: Set<String> = ["dmg", "pkg", "mpkg", "xip", "iso"]
        let partial: Set<String> = ["crdownload", "download", "part"]
        let archives: Set<String> = ["zip", "tar", "gz", "tgz", "rar", "7z"]
        let old = Date().addingTimeInterval(-180 * 86400)

        var items = [CleanItem]()
        for i in info {
            let size = i.isDir ? (dsz[i.path] ?? 0) : i.size
            let ext = (i.name as NSString).pathExtension.lowercased()
            var base = (i.name as NSString).deletingPathExtension
            if base.hasSuffix(".tar") { base = String(base.dropLast(4)) }
            var safety = Safety.review
            var reason: String
            if partial.contains(ext) {
                safety = .safe
                reason = "Muat turun tak lengkap"
            } else if !i.isDir, installers.contains(ext) {
                safety = .safe
                reason = "Fail pemasang, tak perlu selepas dipasang"
            } else if !i.isDir, archives.contains(ext), dirNames.contains(base) {
                safety = .safe
                reason = "Arkib yang dah diekstrak ke folder \(base)"
            } else if !i.isDir, let orig = originalName(of: i.name), let os = fileSize[orig], os == i.size {
                safety = .safe
                reason = "Pendua kepada \(orig)"
            } else {
                let when = i.date.map { df.string(from: $0) } ?? "tarikh tak diketahui"
                reason = (i.isDir ? "Folder" : (ext.isEmpty ? "Fail" : ext.uppercased())) + " · diubah \(when)"
                if let d = i.date, d < old { reason += " · lama tak disentuh" }
            }
            guard size >= (safety == .safe ? 100 * 1024 : 5 * MB) else { continue }
            items.append(CleanItem(name: i.name, path: i.path, detail: reason + " · dialih ke Tong Sampah",
                                   size: size, safety: safety, action: .trash, selected: safety == .safe))
        }
        return items
    }

    // MARK: big files

    static func bigFiles() -> [CleanItem] {
        var items = [CleanItem]()
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey, .isPackageKey]
        for folder in ["Desktop", "Documents", "Movies"] {
            let root = URL(fileURLWithPath: home + "/" + folder)
            guard let en = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in en {
                if en.level > 4 { en.skipDescendants(); continue }
                let name = url.lastPathComponent
                if name == "node_modules" { en.skipDescendants(); continue }
                guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
                let s = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
                if s >= 300 * MB {
                    items.append(CleanItem(name: name, path: url.path, detail: short(url.deletingLastPathComponent().path) + " · dialih ke Tong Sampah",
                                           size: s, safety: .review, action: .trash, selected: false))
                }
            }
        }
        return items
    }
}

/// Buang kiraan berganda: item yang sama dalam dua kategori, atau item yang
/// berada di dalam item lain yang akan dibuang sepenuhnya.
enum Dedupe {
    static func isWhole(_ a: CleanAction) -> Bool {
        switch a {
        case .delete, .deleteContents, .trash, .worktree: return true
        case .trashList, .simulatorErase: return false
        }
    }

    @discardableResult
    static func apply(_ cats: inout [CleanCategory]) -> Int {
        // 1. Folder yang mengandungi git worktree dikunci; worktree dibuang satu-satu.
        let wtPaths = cats.first { $0.id == "worktree" }?.items.map { $0.path } ?? []
        for c in cats.indices where cats[c].id != "worktree" {
            for i in cats[c].items.indices where cats[c].items[i].safety != .locked {
                let prefix = cats[c].items[i].path + "/"
                if wtPaths.contains(where: { $0.hasPrefix(prefix) }) {
                    cats[c].items[i].safety = .locked
                    cats[c].items[i].selected = false
                    cats[c].items[i].detail = "Mengandungi git worktree. Buang melalui kategori Worktree git."
                }
            }
        }
        // 2. Buang item pendua dan item yang sudah diliputi oleh item induk.
        var covers = [String]()
        for c in cats {
            for it in c.items where it.safety != .locked && isWhole(it.action) { covers.append(it.path + "/") }
        }
        var seen = Set<String>()
        var removed = 0
        for c in cats.indices {
            cats[c].items.removeAll { it in
                var drop = false
                if isWhole(it.action) {
                    if seen.contains(it.path) { drop = true } else { seen.insert(it.path) }
                }
                if !drop, covers.contains(where: { it.path.hasPrefix($0) }) { drop = true }
                if drop { removed += 1 }
                return drop
            }
        }
        return removed
    }
}
