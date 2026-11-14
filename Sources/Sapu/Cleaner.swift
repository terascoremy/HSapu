import Foundation

enum Cleaner {
    /// Returns nil on success, or a short error message.
    /// `toTrash`: alih ke Tong Sampah dan bukannya padam terus, supaya boleh dipulihkan.
    /// Tong Sampah sendiri sentiasa dikosongkan terus.
    static func perform(_ item: CleanItem, toTrash: Bool = false) -> String? {
        let fm = FileManager.default
        let useTrash = toTrash && item.path != NSHomeDirectory() + "/.Trash"
        func remove(_ path: String) throws {
            if useTrash { try fm.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil) } else { try fm.removeItem(atPath: path) }
        }
        do {
            switch item.action {
            case .delete:
                try remove(item.path)
                if item.path.hasSuffix(".avd") {
                    try? remove(String(item.path.dropLast(4)) + ".ini")
                }
            case .deleteContents:
                var failed = 0
                for c in try fm.contentsOfDirectory(atPath: item.path) {
                    do { try remove(item.path + "/" + c) } catch { failed += 1 }
                }
                if failed > 0 { return "\(item.name): \(failed) item tak dapat dipadam" }
            case .trash:
                try fm.trashItem(at: URL(fileURLWithPath: item.path), resultingItemURL: nil)
            case .trashList(let paths):
                var failed = 0
                for p in paths {
                    do { try fm.trashItem(at: URL(fileURLWithPath: p), resultingItemURL: nil) } catch { failed += 1 }
                }
                if failed > 0 { return "\(item.name): \(failed) fail tak dapat dialih" }
            case .worktree(let repo):
                let r = Shell.run(Scanner.git, ["-C", repo, "worktree", "remove", item.path], mergeErr: true)
                if r.status != 0 {
                    return "\(item.name): \(r.out.trimmingCharacters(in: .whitespacesAndNewlines))"
                }
            case .simulatorErase:
                _ = Shell.run("/usr/bin/xcrun", ["simctl", "shutdown", "all"])
                let r = Shell.run("/usr/bin/xcrun", ["simctl", "erase", "all"], mergeErr: true)
                if r.status != 0 {
                    return "\(item.name): \(r.out.trimmingCharacters(in: .whitespacesAndNewlines))"
                }
            }
        } catch {
            return "\(item.name): \(error.localizedDescription)"
        }
        return nil
    }
}

enum SelfTest {
    static func run() {
        let fm = FileManager.default
        let root = NSTemporaryDirectory() + "sapu-selftest-" + UUID().uuidString
        var ok = true
        func check(_ label: String, _ cond: Bool) {
            print((cond ? "PASS " : "FAIL ") + label)
            if !cond { ok = false }
        }
        try? fm.createDirectory(atPath: root + "/a/sub", withIntermediateDirectories: true)
        fm.createFile(atPath: root + "/a/sub/f.bin", contents: Data(count: 4096))
        fm.createFile(atPath: root + "/a/g.bin", contents: Data(count: 4096))

        let contents = CleanItem(name: "a", path: root + "/a", detail: "", size: 0, safety: .safe, action: .deleteContents, selected: true)
        check("deleteContents tiada ralat", Cleaner.perform(contents) == nil)
        check("deleteContents kekalkan folder", fm.fileExists(atPath: root + "/a"))
        check("deleteContents kosongkan isi", ((try? fm.contentsOfDirectory(atPath: root + "/a")) ?? ["x"]).isEmpty)

        let del = CleanItem(name: "a", path: root + "/a", detail: "", size: 0, safety: .safe, action: .delete, selected: true)
        check("delete tiada ralat", Cleaner.perform(del) == nil)
        check("delete buang folder", !fm.fileExists(atPath: root + "/a"))

        let repo = root + "/repo"
        try? fm.createDirectory(atPath: repo, withIntermediateDirectories: true)
        let g = Scanner.git
        _ = Shell.run(g, ["-C", repo, "init", "-q", "-b", "main"])
        fm.createFile(atPath: repo + "/x.txt", contents: Data("x".utf8))
        _ = Shell.run(g, ["-C", repo, "add", "."])
        _ = Shell.run(g, ["-C", repo, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "init"])
        let wt = repo + "/.claude/worktrees/w1"
        _ = Shell.run(g, ["-C", repo, "worktree", "add", "-q", "-b", "feat", wt])
        check("worktree dicipta", fm.fileExists(atPath: wt))
        let w = CleanItem(name: "w1", path: wt, detail: "", size: 0, safety: .safe, action: .worktree(repo: repo), selected: true)
        check("worktree remove tiada ralat", Cleaner.perform(w) == nil)
        check("worktree dibuang", !fm.fileExists(atPath: wt))
        check("branch kekal", Shell.run(g, ["-C", repo, "rev-parse", "--verify", "--quiet", "feat"]).status == 0)

        let wt2 = repo + "/.claude/worktrees/w2"
        _ = Shell.run(g, ["-C", repo, "worktree", "add", "-q", "-b", "feat2", wt2])
        fm.createFile(atPath: wt2 + "/new.txt", contents: Data("n".utf8))
        let w2 = CleanItem(name: "w2", path: wt2, detail: "", size: 0, safety: .safe, action: .worktree(repo: repo), selected: true)
        check("worktree kotor ditolak", Cleaner.perform(w2) != nil && fm.fileExists(atPath: wt2))

        try? fm.removeItem(atPath: root)
        print(ok ? "SEMUA LULUS" : "ADA YANG GAGAL")
    }
}
