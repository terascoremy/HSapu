import AppKit
import SwiftUI

struct SapuApp: App {
    @StateObject private var state = AppState()
    @StateObject private var hub = HubState()
    @StateObject private var sims = SimState()

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environmentObject(state)
                .environmentObject(hub)
                .environmentObject(sims)
                .onAppear {
                    hub.refreshAll()
                    let args = CommandLine.arguments
                    if let i = args.firstIndex(of: "--shot"), i + 1 < args.count {
                        state.runShots(to: args[i + 1], hub: hub, sims: sims)
                    } else {
                        state.autoRefresh()
                        state.startMonitor()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarContent().environmentObject(state).environmentObject(hub).environmentObject(sims)
        } label: {
            Image(systemName: "sparkles")
        }
        .menuBarExtraStyle(.window)
    }
}

struct RootView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ZStack {
            Background(theme: state.theme)
            HStack(spacing: 0) {
                Sidebar().frame(width: 272)
                Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)
                detail.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if state.cleaning { CleaningOverlay() }
        }
        .frame(minWidth: 1120, minHeight: 700)
        .foregroundStyle(.white)
        .ignoresSafeArea()
        .sheet(item: $state.pending) { p in CleanSheet(p: p) }
        .alert("Ada item tak dapat dibersihkan", isPresented: $state.showErrors) {
            Button("OK") {}
        } message: {
            Text(state.errors.prefix(5).joined(separator: "\n"))
        }
    }

    @ViewBuilder var detail: some View {
        switch state.selection {
        case .overview: OverviewView()
        case .worktrees: WorktreesView()
        case .builds: BuildsView()
        case .dev: DevView()
        case .simulators: SimView()
        case .settings: SettingsView()
        case .category(let id): CategoryView(categoryID: id).id(id)
        }
    }
}

struct Background: View {
    let theme: Theme

    var body: some View {
        ZStack {
            LinearGradient(colors: [theme.a, theme.b], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [theme.glow.opacity(0.45), .clear], center: UnitPoint(x: 0.55, y: 0.35), startRadius: 0, endRadius: 560)
        }
        .animation(.easeInOut(duration: 0.45), value: theme)
    }
}

// MARK: sidebar

struct Sidebar: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var hub: HubState
    @EnvironmentObject var sims: SimState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").font(.system(size: 20, weight: .bold))
                Text("Sapu").font(.system(size: 22, weight: .bold, design: .rounded))
            }
            .padding(.top, 52)
            .padding(.horizontal, 10)
            .padding(.bottom, 18)

            SidebarRow(icon: "sparkles.rectangle.stack.fill", title: "Ringkasan pembersih", trailing: nil, selected: state.selection == .overview) {
                state.selection = .overview
            }
            Text("Kerja")
                .font(.system(size: 11, weight: .semibold))
                .opacity(0.5)
                .padding(.horizontal, 10)
                .padding(.top, 14)
                .padding(.bottom, 2)
            SidebarRow(icon: "arrow.triangle.branch", title: "Worktree",
                       trailing: hub.attentionCount > 0 ? "\(hub.attentionCount) perhatian" : nil, selected: state.selection == .worktrees) {
                state.selection = .worktrees
            }
            SidebarRow(icon: "shippingbox.fill", title: "Build dan release",
                       trailing: hub.apps.isEmpty ? nil : "\(hub.apps.count) app", selected: state.selection == .builds) {
                state.selection = .builds
            }
            SidebarRow(icon: "gauge.with.dots.needle.67percent", title: "Dev",
                       trailing: hub.runners.isEmpty ? nil : "\(hub.runnersUp)/\(hub.runners.count) runner", selected: state.selection == .dev) {
                state.selection = .dev
            }
            SidebarRow(icon: "iphone.gen3", title: "Simulator",
                       trailing: sims.loaded ? (sims.sizesReady ? fmt(sims.devicesSize + sims.runtimesSize) : "\(sims.devices.count) peranti") : nil,
                       selected: state.selection == .simulators) {
                state.selection = .simulators
            }
            Text("Pembersihan")
                .font(.system(size: 11, weight: .semibold))
                .opacity(0.5)
                .padding(.horizontal, 10)
                .padding(.top, 14)
                .padding(.bottom, 2)
            ForEach(state.categories) { c in
                SidebarRow(icon: c.icon, title: c.title, trailing: c.scanned && c.total > 0 ? fmt(c.total) : nil,
                           selected: state.selection == .category(c.id)) {
                    state.selection = .category(c.id)
                }
            }
            Spacer()
            if let u = state.update {
                Button { state.selection = .settings } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Versi \(u.version) tersedia").font(.system(size: 12.5, weight: .semibold))
                        Spacer()
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(okColor.opacity(0.22)))
                }
                .buttonStyle(.plain)
            }
            SidebarRow(icon: "gearshape.fill", title: "Tetapan", trailing: nil, selected: state.selection == .settings) {
                state.selection = .settings
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("\(fmt(state.diskFree)) kosong").font(.system(size: 13, weight: .semibold))
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15))
                        Capsule().fill(Color.white.opacity(0.85)).frame(width: g.size.width * state.usedFraction)
                    }
                }
                .frame(height: 5)
                Text("daripada \(fmt(state.diskTotal))").font(.system(size: 11)).opacity(0.6)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.07)))
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 12)
        .background(Color.black.opacity(0.2))
    }
}

struct SidebarRow: View {
    let icon: String
    let title: String
    let trailing: String?
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(selected ? 0.22 : 0.1)))
                Text(title).font(.system(size: 13.5, weight: selected ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 4)
                if let trailing {
                    Text(trailing).font(.system(size: 11, weight: .medium)).monospacedDigit().opacity(0.7)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(selected ? 0.16 : (hover ? 0.07 : 0))))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: overview

struct OverviewView: View {
    @EnvironmentObject var state: AppState

    var headline: String {
        if state.scanning && !state.hasScanned { return "Sedang mengimbas" }
        if let f = state.lastFreed { return state.lastWasTrash ? "\(fmt(f)) dialih ke Tong Sampah" : "\(fmt(f)) dibebaskan" }
        if state.hasScanned { return state.totalFound > 0 ? "\(fmt(state.totalFound)) dijumpai" : "Mac ni dah kemas" }
        return "Jom kemas Mac ni"
    }

    var subline: String {
        if state.scanning && !state.hasScanned { return "\(state.scannedCount) daripada \(state.categories.count) kategori siap." }
        if state.hasScanned {
            if state.scanning { return "Mengemas kini di latar. Hasil imbasan terakhir dipaparkan dulu." }
            if state.lastWasTrash, state.lastFreed != nil { return "Kosongkan Tong Sampah untuk bebaskan ruang sebenar." }
            return state.totalSelected > 0
                ? "\(fmt(state.totalSelected)) dah dipilih sebab selamat dibuang. Buka kategori untuk pilih yang lain."
                : "Tiada yang dipilih. Buka kategori untuk pilih item."
        }
        return "Imbas untuk cari cache, fail build, worktree lama dan fail besar."
    }

    var body: some View {
        VStack(spacing: 26) {
            HStack(spacing: 34) {
                DiskRing(fraction: state.usedFraction, free: state.diskFree)
                VStack(alignment: .leading, spacing: 10) {
                    Text(headline).font(.system(size: 36, weight: .bold, design: .rounded))
                    Text(subline).font(.system(size: 15)).opacity(0.8).fixedSize(horizontal: false, vertical: true)
                    if let d = state.lastScan, state.hasScanned {
                        Text("Imbasan terakhir \(ago(d))" + (History.totalFreed > 0 ? " · \(fmt(History.totalFreed)) dibebaskan sepanjang masa" : ""))
                            .font(.system(size: 12)).opacity(0.55)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 56)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 12) {
                ForEach(state.categories) { c in
                    CategoryCard(cat: c, scanning: state.scanning) { state.selection = .category(c.id) }
                }
            }
            Spacer(minLength: 0)
            actionBar
        }
        .padding(.horizontal, 38)
        .padding(.bottom, 30)
    }

    @ViewBuilder var actionBar: some View {
        if state.hasScanned {
            HStack(spacing: 12) {
                PillButton(title: state.scanning ? "Mengimbas" : "Imbas semula", icon: "arrow.clockwise", filled: false) { state.scan() }
                    .disabled(state.scanning)
                PillButton(title: state.totalSelected > 0 ? "Bersihkan \(fmt(state.totalSelected))" : "Tiada pilihan",
                           icon: "sparkles", filled: true, tint: state.theme.a) { state.requestClean(categoryID: nil) }
                    .disabled(state.totalSelected == 0 || state.scanning)
                    .opacity(state.totalSelected == 0 || state.scanning ? 0.5 : 1)
            }
        } else {
            ScanButton(scanning: state.scanning) { state.scan() }
        }
    }
}

struct DiskRing: View {
    let fraction: Double
    let free: Int64

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.14), lineWidth: 16)
            Circle()
                .trim(from: 0, to: max(0.01, min(1, fraction)))
                .stroke(Color.white, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: fraction)
            VStack(spacing: 2) {
                Text("\(Int((fraction * 100).rounded()))%").font(.system(size: 38, weight: .bold, design: .rounded)).monospacedDigit()
                Text("digunakan").font(.system(size: 12)).opacity(0.7)
            }
        }
        .frame(width: 168, height: 168)
    }
}

struct CategoryCard: View {
    let cat: CleanCategory
    let scanning: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: cat.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: 10).fill(cat.theme.glow.opacity(0.85)))
                    Spacer()
                    if cat.scanned && !cat.items.isEmpty {
                        Text("\(cat.items.count) item").font(.system(size: 11)).opacity(0.6)
                    } else {
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).opacity(0.4)
                    }
                }
                Text(cat.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if cat.scanned {
                        Text(cat.total > 0 ? fmt(cat.total) : "Bersih").font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit()
                    } else if scanning {
                        ProgressView().controlSize(.small).tint(.white)
                        Text("Mengimbas").font(.system(size: 12)).opacity(0.6)
                    } else {
                        Text("Belum diimbas").font(.system(size: 12)).opacity(0.5)
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: 24)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(hover ? 0.14 : 0.09)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct ScanButton: View {
    let scanning: Bool
    let action: () -> Void
    @State private var spin = false
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color.white.opacity(hover ? 0.26 : 0.18))
                Circle().stroke(Color.white.opacity(0.35), lineWidth: 2)
                if scanning {
                    Circle()
                        .trim(from: 0, to: 0.28)
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spin)
                        .onAppear { spin = true }
                        .onDisappear { spin = false }
                }
                Text(scanning ? "Mengimbas" : "Imbas").font(.system(size: scanning ? 14 : 19, weight: .semibold, design: .rounded))
            }
            .frame(width: 112, height: 112)
            .shadow(color: .white.opacity(0.25), radius: 24)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(scanning)
        .onHover { hover = $0 }
    }
}

struct PillButton: View {
    let title: String
    let icon: String
    let filled: Bool
    var tint: Color = .black
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                Text(title).font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(filled ? tint : Color.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background(Capsule().fill(filled ? Color.white.opacity(hover ? 0.92 : 1) : Color.white.opacity(hover ? 0.2 : 0.12)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: category

struct CategoryView: View {
    let categoryID: String
    @EnvironmentObject var state: AppState

    var body: some View {
        if let cat = state.categories.first(where: { $0.id == categoryID }) {
            VStack(alignment: .leading, spacing: 0) {
                header(cat)
                Group {
                    if !cat.scanned {
                        placeholder
                    } else if cat.items.isEmpty {
                        message(icon: "checkmark.seal.fill", title: "Bersih", text: "Tiada apa untuk dibuang di sini.")
                    } else {
                        list(cat)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if cat.scanned && !cat.items.isEmpty { bottom(cat) }
            }
        }
    }

    func header(_ cat: CleanCategory) -> some View {
        HStack(spacing: 16) {
            Image(systemName: cat.icon)
                .font(.system(size: 24, weight: .semibold))
                .frame(width: 58, height: 58)
                .background(RoundedRectangle(cornerRadius: 16).fill(cat.theme.glow.opacity(0.85)))
            VStack(alignment: .leading, spacing: 4) {
                Text(cat.title).font(.system(size: 28, weight: .bold, design: .rounded))
                Text(cat.subtitle).font(.system(size: 13.5)).opacity(0.75)
            }
            Spacer()
            if cat.scanned && cat.total > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(fmt(cat.total)).font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                    Text("\(cat.items.count) item").font(.system(size: 12)).opacity(0.65)
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 52)
        .padding(.bottom, 18)
    }

    @ViewBuilder var placeholder: some View {
        if state.scanning {
            VStack(spacing: 12) {
                ProgressView().controlSize(.large).tint(.white)
                Text("Mengimbas").font(.system(size: 14)).opacity(0.7)
            }
        } else {
            VStack(spacing: 16) {
                message(icon: "magnifyingglass", title: "Belum diimbas", text: "Imbas dulu untuk lihat apa yang boleh dibuang.")
                PillButton(title: "Imbas sekarang", icon: "sparkles", filled: true, tint: state.theme.a) { state.scan() }
            }
        }
    }

    func message(icon: String, title: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 40, weight: .semibold)).opacity(0.9)
            Text(title).font(.system(size: 20, weight: .bold, design: .rounded))
            Text(text).font(.system(size: 13)).opacity(0.7)
        }
    }

    func list(_ cat: CleanCategory) -> some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(cat.items) { item in
                    ItemRow(item: item, toggle: { state.toggle(categoryID, item.id) }, exclude: { state.exclude(item.path) })
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 16)
        }
    }

    func bottom(_ cat: CleanCategory) -> some View {
        HStack(spacing: 10) {
            PillButton(title: "Pilih yang selamat", icon: "checkmark.shield", filled: false) {
                state.select(categoryID) { $0.safety == .safe }
            }
            PillButton(title: "Pilih semua", icon: "checklist", filled: false) {
                state.select(categoryID) { _ in true }
            }
            PillButton(title: "Kosongkan", icon: "xmark", filled: false) {
                state.select(categoryID) { _ in false }
            }
            Spacer()
            Text("\(cat.selectedItems.count) dipilih").font(.system(size: 13)).opacity(0.75)
            PillButton(title: cat.selectedSize > 0 ? "Bersihkan \(fmt(cat.selectedSize))" : "Bersihkan",
                       icon: "sparkles", filled: true, tint: cat.theme.a) { state.requestClean(categoryID: categoryID) }
                .disabled(cat.selectedItems.isEmpty || state.scanning)
                .opacity(cat.selectedItems.isEmpty || state.scanning ? 0.5 : 1)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
        .background(Color.black.opacity(0.22))
    }
}

struct ItemRow: View {
    let item: CleanItem
    let toggle: () -> Void
    var exclude: (() -> Void)?
    @State private var hover = false

    var locked: Bool { item.safety == .locked }

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Image(systemName: locked ? "lock.fill" : (item.selected ? "checkmark.circle.fill" : "circle"))
                    .font(.system(size: locked ? 15 : 19))
                    .frame(width: 22)
                    .opacity(locked ? 0.5 : (item.selected ? 1 : 0.55))
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name).font(.system(size: 13.5, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    Text(item.detail).font(.system(size: 11.5)).opacity(0.65).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 8)
                SafetyChip(safety: item.safety)
                Text(fmt(item.size)).font(.system(size: 13.5, weight: .semibold)).monospacedDigit().frame(width: 84, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(item.selected && !locked ? 0.15 : (hover ? 0.1 : 0.07))))
            .opacity(locked ? 0.7 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .contextMenu {
            Button("Tunjuk dalam Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
            }
            if let exclude {
                Button("Jangan sentuh item ini lagi") { exclude() }
            }
        }
    }
}

struct SafetyChip: View {
    let safety: Safety

    var label: String {
        switch safety {
        case .safe: return "Selamat"
        case .review: return "Semak dulu"
        case .locked: return "Dikunci"
        }
    }

    var color: Color {
        switch safety {
        case .safe: return Color(hex: 0x4ADE80)
        case .review: return Color(hex: 0xFACC15)
        case .locked: return Color(hex: 0xF87171)
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.black.opacity(0.25)))
    }
}

struct CleaningOverlay: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
            VStack(spacing: 14) {
                Text("Sedang membersih").font(.system(size: 20, weight: .bold, design: .rounded))
                ProgressView(value: state.cleanProgress).tint(.white).frame(width: 300)
                Text(state.cleanLabel).font(.system(size: 12)).opacity(0.7).lineLimit(1).truncationMode(.middle).frame(width: 300)
            }
            .padding(28)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color.black.opacity(0.5)))
        }
    }
}
