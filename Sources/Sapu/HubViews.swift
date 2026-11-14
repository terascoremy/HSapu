import AppKit
import SwiftUI

// MARK: themes

extension Theme {
    static let worktrees = Theme(id: "worktrees", a: Color(hex: 0x0B4A63), b: Color(hex: 0x03161F), glow: Color(hex: 0x38BDF8))
    static let builds = Theme(id: "builds", a: Color(hex: 0x4B2A85), b: Color(hex: 0x140A28), glow: Color(hex: 0xA78BFA))
    static let dev = Theme(id: "dev", a: Color(hex: 0x14532D), b: Color(hex: 0x03150B), glow: Color(hex: 0x4ADE80))
}

// MARK: shared pieces

struct SectionHeader: View {
    let icon: String
    let title: String
    let subtitle: String
    let glow: Color
    var trailing: String?
    var trailingNote: String?

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .semibold))
                .frame(width: 58, height: 58)
                .background(RoundedRectangle(cornerRadius: 16).fill(glow.opacity(0.85)))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 28, weight: .bold, design: .rounded))
                Text(subtitle).font(.system(size: 13.5)).opacity(0.75)
            }
            Spacer()
            if let trailing {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(trailing).font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                    if let trailingNote { Text(trailingNote).font(.system(size: 12)).opacity(0.65) }
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 52)
        .padding(.bottom, 16)
    }
}

struct Panel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}

struct Chip: View {
    let text: String
    var color: Color = .white
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.18)))
            .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 0.5))
    }
}

struct IconButton: View {
    let icon: String
    let help: String
    var disabled = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(hover ? 0.2 : 0.1)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .help(help)
        .onHover { hover = $0 }
    }
}

struct FilterChip: View {
    let title: String
    let count: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                Text("\(count)").font(.system(size: 11)).monospacedDigit().opacity(0.7)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(selected ? 0.24 : 0.09)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

let okColor = Color(hex: 0x4ADE80)
let warnColor = Color(hex: 0xFACC15)
let badColor = Color(hex: 0xF87171)

// MARK: worktrees

enum WTFilter: CaseIterable {
    case all, attention, merged, open

    var title: String {
        switch self {
        case .all: return "Semua"
        case .attention: return "Perlu perhatian"
        case .merged: return "Dah merge"
        case .open: return "Belum merge"
        }
    }

    func matches(_ w: WorktreeInfo) -> Bool {
        switch self {
        case .all: return true
        case .attention: return w.needsAttention
        case .merged: return w.merged && !w.needsAttention
        case .open: return !w.merged && !w.needsAttention
        }
    }
}

struct WorktreesView: View {
    @EnvironmentObject var hub: HubState
    @State private var filter: WTFilter = .all
    @State private var repo = "Semua repo"
    @State private var confirmBulk = false
    @State private var pending: WorktreeInfo?

    var repos: [String] { ["Semua repo"] + Array(Set(hub.worktrees.map { $0.repoName })).sorted() }

    var shown: [WorktreeInfo] {
        hub.worktrees
            .filter { filter.matches($0) && (repo == "Semua repo" || $0.repoName == repo) }
            .sorted { a, b in
                if a.needsAttention != b.needsAttention { return a.needsAttention }
                return (a.size ?? 0) > (b.size ?? 0)
            }
    }

    var bulk: [WorktreeInfo] { shown.filter { $0.safeToRemove } }
    var bulkSize: Int64 { bulk.reduce(0) { $0 + ($1.size ?? 0) } }
    var totalSize: Int64 { hub.worktrees.reduce(0) { $0 + ($1.size ?? 0) } }
    var sizesReady: Bool { !hub.worktrees.isEmpty && !hub.worktrees.contains { $0.size == nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(icon: "arrow.triangle.branch", title: "Worktree dan sesi",
                          subtitle: "Semua git worktree merentas projek kau, dengan status sebenar.",
                          glow: Theme.worktrees.glow,
                          trailing: hub.worktrees.isEmpty ? nil : (sizesReady ? fmt(totalSize) : "Mengira saiz"),
                          trailingNote: hub.worktrees.isEmpty ? nil : "\(hub.worktrees.count) worktree")
            filters
            Group {
                if hub.loadingWT && hub.worktrees.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large).tint(.white)
                        Text("Membaca status git").font(.system(size: 14)).opacity(0.7)
                    }
                } else if shown.isEmpty {
                    Text("Tiada worktree dalam paparan ini.").font(.system(size: 14)).opacity(0.7)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(shown) { w in row(w) }
                        }
                        .padding(.horizontal, 32)
                        .padding(.bottom, 16)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            bottom
        }
        .alert("Buang \(bulk.count) worktree?", isPresented: $confirmBulk) {
            Button("Batal", role: .cancel) {}
            Button("Buang", role: .destructive) { hub.remove(bulk) }
        } message: {
            Text("Semuanya dah merge dan bersih. Folder dibuang, branch kekal dalam repo.")
        }
        .alert("Buang worktree ini?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button("Batal", role: .cancel) {}
            Button("Buang", role: .destructive) { if let p = pending { hub.remove([p]) } }
        } message: {
            Text(pending.map { "\($0.name) dalam \($0.repoName). Branch kekal dalam repo." } ?? "")
        }
    }

    var filters: some View {
        HStack(spacing: 8) {
            ForEach(WTFilter.allCases, id: \.title) { f in
                FilterChip(title: f.title, count: hub.worktrees.filter { f.matches($0) }.count, selected: filter == f) { filter = f }
            }
            Spacer()
            Picker("", selection: $repo) {
                ForEach(repos, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .frame(width: 170)
            IconButton(icon: "arrow.clockwise", help: "Imbas semula", disabled: hub.loadingWT) { hub.loadWorktrees() }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 12)
    }

    func row(_ w: WorktreeInfo) -> some View {
        HStack(spacing: 12) {
            Image(systemName: w.needsAttention ? "exclamationmark.triangle.fill" : (w.merged ? "checkmark.circle.fill" : "circle.dashed"))
                .font(.system(size: 17))
                .foregroundStyle(w.needsAttention ? badColor : (w.merged ? okColor : warnColor))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(w.name).font(.system(size: 13.5, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                Text(detail(w)).font(.system(size: 11.5)).opacity(0.65).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(ago(w.lastCommit)).font(.system(size: 11.5)).opacity(0.6).frame(width: 90, alignment: .trailing)
            Text(w.size.map(fmt) ?? "...").font(.system(size: 13, weight: .semibold)).monospacedDigit().frame(width: 74, alignment: .trailing)
            HStack(spacing: 6) {
                IconButton(icon: "terminal", help: "Buka di Terminal") { Opener.terminal(w.path) }
                IconButton(icon: "chevron.left.forwardslash.chevron.right", help: "Buka di editor", disabled: Opener.editorURL() == nil) { Opener.editor(w.path) }
                IconButton(icon: "folder", help: "Tunjuk di Finder") { Opener.finder(w.path) }
                IconButton(icon: "trash", help: w.removable ? "Buang worktree" : "Ada kerja belum selamat, tak boleh dibuang", disabled: !w.removable || hub.busy) { pending = w }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.07)))
    }

    func detail(_ w: WorktreeInfo) -> String {
        var parts = [w.repoName, w.branch]
        if !w.valid { parts.append("bukan worktree git yang sah") }
        if w.dirty > 0 { parts.append("\(w.dirty) fail belum commit") }
        if w.unpushed > 0 { parts.append("\(w.unpushed) commit belum push") }
        if w.merged && !w.needsAttention { parts.append("dah merge") }
        return parts.joined(separator: " · ")
    }

    var bottom: some View {
        HStack(spacing: 12) {
            if let m = hub.message { Text(m).font(.system(size: 12.5)).opacity(0.85).lineLimit(2) }
            Spacer()
            PillButton(title: bulk.isEmpty ? "Tiada yang dah merge" : "Buang \(bulk.count) yang dah merge" + (sizesReady ? " (\(fmt(bulkSize)))" : ""),
                       icon: "sparkles", filled: true, tint: Theme.worktrees.a) { confirmBulk = true }
                .disabled(bulk.isEmpty || hub.busy)
                .opacity(bulk.isEmpty || hub.busy ? 0.5 : 1)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
        .background(Color.black.opacity(0.22))
    }
}

// MARK: builds

struct BuildsView: View {
    @EnvironmentObject var hub: HubState
    @State private var open: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(icon: "shippingbox.fill", title: "Build dan release",
                          subtitle: "Versi dan nombor build setiap app, status CI dan senarai semak sebelum submit.",
                          glow: Theme.builds.glow,
                          trailing: hub.apps.isEmpty ? nil : "\(hub.apps.count) app", trailingNote: nil)
            if hub.loadingApps && hub.apps.isEmpty {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large).tint(.white)
                    Text("Mencari app dalam projek kau").font(.system(size: 14)).opacity(0.7)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if hub.apps.isEmpty {
                Text("Tiada app dijumpai.").font(.system(size: 14)).opacity(0.7).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(hub.apps) { app in card(app) }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    func ciChip(_ s: CIStatus?) -> some View {
        guard let s else { return AnyView(Chip(text: "CI tiada data").opacity(0.7)) }
        let (label, color): (String, Color)
        switch s.state {
        case "success": (label, color) = ("CI lulus", okColor)
        case "failure", "timed_out", "startup_failure": (label, color) = ("CI gagal", badColor)
        case "in_progress", "queued", "waiting", "pending": (label, color) = ("CI sedang jalan", warnColor)
        case "cancelled": (label, color) = ("CI dibatalkan", warnColor)
        default: (label, color) = ("CI " + s.state, .white)
        }
        return AnyView(Chip(text: label + (s.when != nil ? " · " + ago(s.when) : ""), color: color))
    }

    func card(_ app: BuildApp) -> some View {
        let checks = hub.checklists[app.id] ?? Array(repeating: false, count: HubState.checklistItems.count)
        let done = checks.filter { $0 }.count
        let expanded = open.contains(app.id)
        return Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(app.name).font(.system(size: 17, weight: .bold, design: .rounded))
                            Chip(text: app.kind)
                            Chip(text: app.repoName, color: Theme.builds.glow)
                        }
                        Text(app.bundleId ?? "bundle id tak dijumpai").font(.system(size: 12, design: .monospaced)).opacity(0.65)
                    }
                    Spacer()
                    ciChip(app.ci)
                }
                HStack(spacing: 22) {
                    stat("Versi", app.version)
                    stat("iOS build", app.iosBuild)
                    stat("Android code", app.androidCode)
                    stat("Branch", app.branch.isEmpty ? nil : app.branch)
                    stat("Commit terakhir", app.lastCommit.map { ago($0) })
                    Spacer(minLength: 0)
                }
                if let t = app.ci?.title, !t.isEmpty {
                    Text("Larian CI terakhir: " + t).font(.system(size: 12)).opacity(0.6).lineLimit(1)
                }
                HStack(spacing: 8) {
                    Button {
                        if expanded { open.remove(app.id) } else { open.insert(app.id) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 10, weight: .bold))
                            Text("Senarai semak \(done)/\(HubState.checklistItems.count)").font(.system(size: 12.5, weight: .semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    IconButton(icon: "terminal", help: "Buka di Terminal") { Opener.terminal(app.dir) }
                    IconButton(icon: "folder", help: "Tunjuk di Finder") { Opener.finder(app.dir) }
                    IconButton(icon: "safari", help: "Buka repo di GitHub", disabled: app.remoteURL == nil) {
                        if let u = app.remoteURL { Opener.url(u + "/actions") }
                    }
                }
                if expanded {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(HubState.checklistItems.enumerated()), id: \.offset) { i, text in
                            Button { hub.toggleCheck(app, i) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: checks[i] ? "checkmark.circle.fill" : "circle").font(.system(size: 16))
                                        .foregroundStyle(checks[i] ? okColor : Color.white.opacity(0.6))
                                    Text(text).font(.system(size: 13)).strikethrough(checks[i], color: .white.opacity(0.5)).opacity(checks[i] ? 0.6 : 1)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        if done > 0 {
                            Button("Set semula senarai semak") { hub.resetChecks(app) }
                                .buttonStyle(.plain).font(.system(size: 12)).opacity(0.6)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    func stat(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 11)).opacity(0.55)
            Text(value ?? "tiada").font(.system(size: 13.5, weight: .semibold)).monospacedDigit().lineLimit(1)
        }
    }
}

// MARK: dev

struct DevView: View {
    @EnvironmentObject var hub: HubState
    @EnvironmentObject var state: AppState

    var low: Bool { state.diskFree < 50 * 1_073_741_824 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(icon: "gauge.with.dots.needle.67percent", title: "Dev",
                          subtitle: "Runner CI, Docker, simulator dan ruang disk di satu tempat.",
                          glow: Theme.dev.glow,
                          trailing: "\(fmt(state.diskFree)) kosong", trailingNote: "daripada \(fmt(state.diskTotal))")
            ScrollView {
                VStack(spacing: 14) {
                    if low {
                        Panel {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(warnColor)
                                Text("Ruang disk tinggal kurang 50 GB. Buka Pembersih untuk bebaskan ruang.").font(.system(size: 13.5, weight: .medium))
                                Spacer()
                                PillButton(title: "Buka Pembersih", icon: "sparkles", filled: false) { state.selection = .overview }
                            }
                        }
                    }
                    runnersPanel
                    HStack(alignment: .top, spacing: 14) {
                        dockerPanel
                        devicesPanel
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
            }
        }
    }

    var runnersPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Runner GitHub Actions").font(.system(size: 15, weight: .semibold))
                    Chip(text: "\(hub.runnersUp) daripada \(hub.runners.count) berjalan", color: hub.runnersUp > 0 ? okColor : .white)
                    Spacer()
                    if hub.runners.contains(where: { !$0.running }) {
                        PillButton(title: "Mulakan semua", icon: "play.fill", filled: false) { hub.runners.filter { !$0.running }.forEach { hub.start($0) } }
                    }
                    if hub.runnersUp > 0 {
                        PillButton(title: "Hentikan semua", icon: "stop.fill", filled: false) { hub.runners.filter { $0.running && !$0.busy }.forEach { hub.stop($0) } }
                    }
                }
                if hub.runners.isEmpty {
                    Text("Tiada runner dijumpai dalam folder home.").font(.system(size: 13)).opacity(0.65)
                }
                ForEach(hub.runners) { r in
                    HStack(spacing: 12) {
                        Circle().fill(r.busy ? warnColor : (r.running ? okColor : Color.white.opacity(0.3))).frame(width: 9, height: 9)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.name).font(.system(size: 13.5, weight: .semibold))
                            Text(r.repo.isEmpty ? Scanner.short(r.dir) : r.repo + " · " + Scanner.short(r.dir)).font(.system(size: 11.5)).opacity(0.6)
                        }
                        Spacer()
                        Text(r.busy ? "Sibuk menjalankan job" : (r.running ? "Menunggu job" : "Berhenti")).font(.system(size: 12)).opacity(0.75)
                        if r.running {
                            IconButton(icon: "stop.fill", help: r.busy ? "Sedang menjalankan job" : "Hentikan runner", disabled: r.busy) { hub.stop(r) }
                        } else {
                            IconButton(icon: "play.fill", help: "Mulakan runner") { hub.start(r) }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    var dockerPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                Text("Docker").font(.system(size: 15, weight: .semibold))
                if !hub.docker.installed {
                    Text("Docker tak dipasang.").font(.system(size: 13)).opacity(0.65)
                } else if hub.docker.running {
                    HStack(spacing: 8) {
                        Circle().fill(okColor).frame(width: 9, height: 9)
                        Text("Berjalan").font(.system(size: 13.5, weight: .semibold))
                    }
                    Text("\(hub.docker.up) container aktif, \(hub.docker.total) kesemuanya.").font(.system(size: 12.5)).opacity(0.7)
                } else {
                    HStack(spacing: 8) {
                        Circle().fill(Color.white.opacity(0.3)).frame(width: 9, height: 9)
                        Text("Tak berjalan").font(.system(size: 13.5, weight: .semibold))
                    }
                    PillButton(title: "Buka Docker", icon: "play.fill", filled: false) { hub.openDocker() }
                }
            }
        }
    }

    var devicesPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                Text("Simulator dan emulator").font(.system(size: 15, weight: .semibold))
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(hub.bootedSims) simulator iOS hidup").font(.system(size: 13.5, weight: .semibold))
                        Text("Simulator yang hidup makan RAM dan bateri.").font(.system(size: 11.5)).opacity(0.6)
                    }
                    Spacer()
                    if hub.bootedSims > 0 {
                        PillButton(title: "Matikan semua", icon: "power", filled: false) { hub.shutdownSims() }
                    }
                }
                Divider().opacity(0.3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(hub.emulators) emulator Android hidup, \(hub.avds.count) AVD").font(.system(size: 13.5, weight: .semibold))
                    Text(hub.avds.isEmpty ? "Tiada AVD" : hub.avds.joined(separator: ", ")).font(.system(size: 11.5)).opacity(0.6).lineLimit(2)
                }
            }
        }
    }
}

// MARK: menu bar

struct MenuBarContent: View {
    @EnvironmentObject var hub: HubState
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    func go(_ s: Selection) {
        state.selection = s
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "sparkles")
                Text("Sapu").font(.system(size: 14, weight: .bold, design: .rounded))
                Spacer()
            }
            line("internaldrive", "\(fmt(state.diskFree)) kosong", state.diskFree < 50 * 1_073_741_824 ? badColor : nil) { go(.overview) }
            line("play.circle", "\(hub.runnersUp) daripada \(hub.runners.count) runner CI berjalan", nil) { go(.dev) }
            line("arrow.triangle.branch", hub.worktrees.isEmpty ? "Worktree belum diimbas" : "\(hub.attentionCount) worktree perlu perhatian, \(hub.safeWorktrees.count) boleh dibuang",
                 hub.attentionCount > 0 ? warnColor : nil) { go(.worktrees) }
            line("shippingbox", "\(hub.apps.count) app dijejak", nil) { go(.builds) }
            Divider()
            HStack {
                Button("Buka Sapu") { go(.overview) }
                Spacer()
                Button("Imbas semula") { hub.refreshAll() }
                Button("Keluar") { NSApp.terminate(nil) }
            }
            .font(.system(size: 12))
        }
        .padding(14)
        .frame(width: 330)
        .onAppear { if hub.worktrees.isEmpty && !hub.loadingWT { hub.refreshAll() } }
    }

    func line(_ icon: String, _ text: String, _ color: Color?, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 18).foregroundStyle(color ?? Color.primary)
                Text(text).font(.system(size: 12.5)).foregroundStyle(color ?? Color.primary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
