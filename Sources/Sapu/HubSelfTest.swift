import AppKit
import Foundation

enum HubSelfTest {
    static func run() {
        var ok = true
        func check(_ label: String, _ cond: Bool) {
            print((cond ? "PASS " : "FAIL ") + label)
            if !cond { ok = false }
        }
        let fm = FileManager.default
        let root = NSTemporaryDirectory() + "sapu-hubtest-" + UUID().uuidString
        try? fm.createDirectory(atPath: root + "/runner/bin", withIntermediateDirectories: true)

        // Runner palsu: run.sh -> bin/Runner.Listener (skrip python yang tidur sehingga SIGINT)
        let listener = root + "/runner/bin/Runner.Listener"
        try? "#!/usr/bin/env python3\nimport time\ntime.sleep(300)\n".write(toFile: listener, atomically: true, encoding: .utf8)
        try? "#!/bin/bash\nDIR=\"$(cd \"$(dirname \"$0\")\" && pwd)\"\nexec \"$DIR\"/bin/Runner.Listener \"$@\"\n"
            .write(toFile: root + "/runner/run.sh", atomically: true, encoding: .utf8)
        _ = Shell.run("/bin/chmod", ["+x", listener, root + "/runner/run.sh"])

        func listenerRunning() -> Bool {
            Shell.run("/bin/ps", ["-axo", "command="]).out.contains(root + "/runner/bin/Runner.Listener")
        }
        func waitFor(_ want: Bool, seconds: Double = 6) -> Bool {
            let end = Date().addingTimeInterval(seconds)
            while Date() < end {
                if listenerRunning() == want { return true }
                Thread.sleep(forTimeInterval: 0.3)
            }
            return listenerRunning() == want
        }

        check("runner palsu belum berjalan", !listenerRunning())
        HubScan.startRunner(root + "/runner", name: "ujian")
        let started = waitFor(true)
        check("butang Mulakan: runner berjalan", started)
        HubScan.stopRunner(root + "/runner")
        check("butang Hentikan: runner berhenti", waitFor(false))
        check("log runner ditulis", fm.fileExists(atPath: NSHomeDirectory() + "/Library/Logs/Sapu-runner-ujian.log"))
        try? fm.removeItem(atPath: NSHomeDirectory() + "/Library/Logs/Sapu-runner-ujian.log")

        // Senarai semak: simpan dan set semula melalui UserDefaults
        MainActor.assumeIsolated {
            let hub = HubState()
            let app = BuildApp(name: "Ujian", dir: root + "/app", repoName: "ujian", repoPath: root, kind: "Expo")
            hub.toggleCheck(app, 1)
            hub.toggleCheck(app, 3)
            let saved = UserDefaults.standard.array(forKey: "sapu.checklist." + app.id) as? [Bool]
            check("senarai semak disimpan", saved == [false, true, false, true, false])
            hub.toggleCheck(app, 1)
            check("senarai semak boleh dinyahtanda", hub.checklists[app.id] == [false, false, false, true, false])
            hub.resetChecks(app)
            check("senarai semak set semula", hub.checklists[app.id] == nil && UserDefaults.standard.array(forKey: "sapu.checklist." + app.id) == nil)
        }

        // Buang worktree melalui HubState (laluan yang sama dengan butang tong sampah)
        let repo = root + "/repo"
        try? fm.createDirectory(atPath: repo, withIntermediateDirectories: true)
        let g = Scanner.git
        _ = Shell.run(g, ["-C", repo, "init", "-q", "-b", "main"])
        fm.createFile(atPath: repo + "/x.txt", contents: Data("x".utf8))
        _ = Shell.run(g, ["-C", repo, "add", "."])
        _ = Shell.run(g, ["-C", repo, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "init"])
        let wt = root + "/wt-merged"
        _ = Shell.run(g, ["-C", repo, "worktree", "add", "-q", "-b", "done", wt])
        let wtDirty = root + "/wt-dirty"
        _ = Shell.run(g, ["-C", repo, "worktree", "add", "-q", "-b", "wip", wtDirty])
        fm.createFile(atPath: wtDirty + "/edit.txt", contents: Data("e".utf8))
        let clean = WorktreeInfo(repoName: "repo", repoPath: repo, path: wt, name: "wt-merged", branch: "done", valid: true,
                                 dirty: 0, unpushed: 0, merged: true, lastCommit: nil, size: nil)
        let dirty = WorktreeInfo(repoName: "repo", repoPath: repo, path: wtDirty, name: "wt-dirty", branch: "wip", valid: true,
                                 dirty: 1, unpushed: 0, merged: false, lastCommit: nil, size: nil)
        check("status: bersih dan merge boleh dibuang", clean.safeToRemove && !clean.needsAttention)
        check("status: ada fail belum commit dikunci", dirty.needsAttention && !dirty.removable)

        MainActor.assumeIsolated {
            let hub = HubState()
            hub.worktrees = [clean, dirty]
            hub.remove([clean])
        }
        let end = Date().addingTimeInterval(8)
        while Date() < end, fm.fileExists(atPath: wt) { RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }
        check("butang Buang: worktree bersih dibuang", !fm.fileExists(atPath: wt))
        check("butang Buang: branch kekal", Shell.run(g, ["-C", repo, "rev-parse", "--verify", "--quiet", "done"]).status == 0)
        check("worktree kotor tak disentuh", fm.fileExists(atPath: wtDirty + "/edit.txt"))
        let blocked = Cleaner.perform(CleanItem(name: "wt-dirty", path: wtDirty, detail: "", size: 0, safety: .safe, action: .worktree(repo: repo), selected: true))
        check("git sendiri menolak buang worktree kotor", blocked != nil && fm.fileExists(atPath: wtDirty))

        // Imbasan sebenar (baca sahaja)
        let apps = HubScan.apps()
        check("imbas app: jumpa app", !apps.isEmpty)
        check("imbas app: faas ada nombor build iOS", apps.contains { $0.bundleId == "my.faas.app" && $0.iosBuild != nil })
        check("imbas app: iqamah (iOS asli) ada versi", apps.contains { $0.bundleId == "my.iqamah.app" && $0.version != nil })
        let runners = HubScan.runners()
        check("imbas runner: jumpa runner", !runners.isEmpty && runners.allSatisfy { !$0.repo.isEmpty })
        let d = HubScan.docker()
        check("docker: status dibaca (\(d.installed ? (d.running ? "berjalan" : "berhenti") : "tiada"))", true)
        print("   simulator hidup: \(HubScan.bootedSims()), AVD: \(HubScan.avds().count)")
        check("editor dijumpai untuk butang kod", Opener.editorURL() != nil)

        // Buka Terminal pada folder sementara
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            let sem = DispatchSemaphore(value: 0)
            var err: Error?
            NSWorkspace.shared.open([URL(fileURLWithPath: root)], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, e in
                err = e
                sem.signal()
            }
            _ = sem.wait(timeout: .now() + 10)
            check("butang Terminal: dibuka tanpa ralat", err == nil)
        }

        _ = Shell.run(g, ["-C", repo, "worktree", "prune"])
        try? fm.removeItem(atPath: root)
        print(ok ? "SEMUA LULUS" : "ADA YANG GAGAL")
    }
}
