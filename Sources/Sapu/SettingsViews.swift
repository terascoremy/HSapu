import AppKit
import SwiftUI

// MARK: pratonton sebelum padam

func actionLabel(_ item: CleanItem, trash: Bool) -> String {
    if item.path == NSHomeDirectory() + "/.Trash" { return "Dikosongkan terus" }
    switch item.action {
    case .delete, .deleteContents: return trash ? "Ke Tong Sampah" : "Dipadam terus"
    case .trash, .trashList: return "Ke Tong Sampah"
    case .worktree: return "Worktree dibuang, branch kekal"
    case .simulatorErase: return "Semua simulator di-erase"
    }
}

struct CleanSheet: View {
    let p: PendingClean
    @EnvironmentObject var state: AppState
    @State private var toTrash = Prefs.trashFirst

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Bersihkan \(p.count) item?").font(.system(size: 20, weight: .bold, design: .rounded))
                Text("\(fmt(p.total)) daripada \(p.title). Semak senarai dulu.").font(.system(size: 13)).opacity(0.7)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(p.groups, id: \.title) { g in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(g.title) · \(g.items.count)").font(.system(size: 12, weight: .semibold)).opacity(0.6)
                            ForEach(g.items) { it in
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(it.name).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                                        Text(actionLabel(it, trash: toTrash)).font(.system(size: 11.5)).opacity(0.6)
                                    }
                                    Spacer(minLength: 6)
                                    SafetyChip(safety: it.safety)
                                    Text(fmt(it.size)).font(.system(size: 13, weight: .semibold)).monospacedDigit().frame(width: 76, alignment: .trailing)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.07)))
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            Toggle(isOn: $toTrash) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Alih ke Tong Sampah, bukannya padam terus").font(.system(size: 13, weight: .medium))
                    Text("Boleh dipulihkan, tapi ruang hanya bebas selepas Tong Sampah dikosongkan.").font(.system(size: 11.5)).opacity(0.6)
                }
            }
            .toggleStyle(.switch)
            HStack {
                Button("Batal") { state.pending = nil }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(toTrash ? "Alih \(fmt(p.total))" : "Bersihkan \(fmt(p.total))") {
                    Prefs.trashFirst = toTrash
                    state.pending = nil
                    state.clean(categoryID: p.categoryID, toTrash: toTrash)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 580, height: 560)
        .background(Color(hex: 0x15121F))
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
    }
}

// MARK: tetapan

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var tick = 0
    @State private var checking = false
    @State private var updateNote: String?
    @State private var downloading = false
    @State private var loginError: String?
    @State private var fda: Bool? = Access.fullDisk()
    @State private var notifDenied = false

    var lowDisk: Binding<Bool> {
        Binding(get: { Prefs.lowDiskAlert }, set: { on in
            Prefs.lowDiskAlert = on
            tick += 1
            if on { Notifier.requestAuth { notifDenied = !$0 && Notifier.available } }
        })
    }

    var scanDays: Binding<Int> {
        Binding(get: { Prefs.scanEveryDays }, set: { v in
            Prefs.scanEveryDays = v
            tick += 1
            if v > 0 { Notifier.requestAuth { notifDenied = !$0 && Notifier.available } }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(icon: "gearshape.fill", title: "Tetapan", subtitle: "Kemas kini, pemantauan, kecualian dan sejarah.",
                          glow: Theme.overview.glow,
                          trailing: History.totalFreed > 0 ? fmt(History.totalFreed) : nil, trailingNote: "dibebaskan sepanjang masa")
            ScrollView {
                VStack(spacing: 14) {
                    updatesPanel
                    monitorPanel
                    accessPanel
                    exclusionsPanel
                    historyPanel
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
            }
        }
        .id(tick)
    }

    // kemas kini

    var updatesPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Kemas kini").font(.system(size: 15, weight: .semibold))
                    Chip(text: "Versi \(appVersion)")
                    Spacer()
                    PillButton(title: checking ? "Menyemak" : "Semak sekarang", icon: "arrow.triangle.2.circlepath", filled: false) {
                        checking = true
                        updateNote = nil
                        state.checkUpdates { r in
                            checking = false
                            switch r {
                            case .available(let i): updateNote = "Versi \(i.version) tersedia."
                            case .upToDate: updateNote = "Sapu dah versi terkini."
                            case .failed(let m): updateNote = m
                            }
                        }
                    }
                    .disabled(checking)
                }
                if let u = state.update {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Versi \(u.version) tersedia").font(.system(size: 13.5, weight: .semibold))
                            if !u.notes.isEmpty { Text(u.notes).font(.system(size: 12)).opacity(0.7).lineLimit(5) }
                        }
                        Spacer()
                        PillButton(title: downloading ? "Memuat turun" : "Muat turun", icon: "arrow.down.circle", filled: true, tint: Theme.overview.a) {
                            downloading = true
                            Task.detached {
                                let err = Updater.download(u)
                                await MainActor.run {
                                    downloading = false
                                    updateNote = err ?? "Dmg dibuka. Seret Sapu ke Applications untuk ganti versi lama."
                                }
                            }
                        }
                        .disabled(downloading || u.dmgName == nil)
                    }
                }
                if let n = updateNote { Text(n).font(.system(size: 12.5)).opacity(0.8) }
                Toggle("Semak kemas kini sekali sehari", isOn: Binding(get: { Prefs.checkUpdates }, set: { Prefs.checkUpdates = $0; tick += 1 }))
                    .toggleStyle(.switch).font(.system(size: 13))
                Text("Semakan guna GitHub CLI (gh) yang dah log masuk, sebab repo Sapu peribadi.").font(.system(size: 11.5)).opacity(0.55)
            }
        }
    }

    // pemantauan

    var monitorPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                Text("Pemantauan").font(.system(size: 15, weight: .semibold))
                HStack {
                    Toggle("Beritahu bila ruang cakera kurang daripada", isOn: lowDisk).toggleStyle(.switch).font(.system(size: 13))
                    Stepper("\(Prefs.lowDiskGB) GB", value: Binding(get: { Prefs.lowDiskGB }, set: { Prefs.lowDiskGB = $0; tick += 1 }), in: 10...500, step: 10)
                        .font(.system(size: 13)).frame(width: 130)
                    Spacer()
                }
                HStack {
                    Text("Imbas automatik di latar").font(.system(size: 13))
                    Picker("", selection: scanDays) {
                        Text("Mati").tag(0)
                        Text("Setiap hari").tag(1)
                        Text("Setiap minggu").tag(7)
                    }
                    .labelsHidden()
                    .frame(width: 150)
                    Spacer()
                }
                Toggle("Buka Sapu semasa log masuk", isOn: Binding(get: { LoginItem.enabled }, set: { loginError = LoginItem.set($0); tick += 1 }))
                    .toggleStyle(.switch).font(.system(size: 13))
                if let e = loginError { Text(e).font(.system(size: 12)).foregroundStyle(warnColor) }
                if notifDenied { Text("Notifikasi disekat. Benarkan Sapu dalam Tetapan Sistem > Notifikasi.").font(.system(size: 12)).foregroundStyle(warnColor) }
                Text(Notifier.available
                     ? "Pemantauan hanya berjalan selagi Sapu dibuka (ikon di bar menu)."
                     : "Notifikasi hanya berfungsi bila Sapu dibuka sebagai app (.app), bukan dari terminal.")
                    .font(.system(size: 11.5)).opacity(0.55)
            }
        }
    }

    // akses cakera penuh

    var accessPanel: some View {
        Panel {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Akses Cakera Penuh").font(.system(size: 15, weight: .semibold))
                        switch fda {
                        case .some(true): Chip(text: "Aktif", color: okColor)
                        case .some(false): Chip(text: "Tiada", color: warnColor)
                        case .none: Chip(text: "Tak pasti")
                        }
                    }
                    Text(fda == false
                         ? "Tanpa ini Sapu tak dapat mengimbas folder dilindungi macOS (Safari, Mail, Messages). Folder lain berfungsi seperti biasa."
                         : "Membolehkan Sapu mengimbas folder dilindungi macOS.")
                        .font(.system(size: 12)).opacity(0.65).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                PillButton(title: "Buka Tetapan", icon: "lock.open", filled: false) { Access.openSettings() }
                IconButton(icon: "arrow.clockwise", help: "Semak semula") { fda = Access.fullDisk() }
            }
        }
    }

    // kecualian

    var exclusionsPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Jangan sentuh").font(.system(size: 15, weight: .semibold))
                    Chip(text: "\(Exclusions.list.count)")
                    Spacer()
                }
                if Exclusions.list.isEmpty {
                    Text("Klik kanan mana-mana item dalam pembersih dan pilih \"Jangan sentuh\" untuk tambah di sini. Item ini tak akan muncul atau dipadam.")
                        .font(.system(size: 12.5)).opacity(0.65)
                }
                ForEach(Exclusions.list, id: \.self) { p in
                    HStack {
                        Image(systemName: "lock.shield").opacity(0.6)
                        Text(Scanner.short(p)).font(.system(size: 12.5)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        IconButton(icon: "xmark", help: "Benarkan semula (imbas semula untuk nampak)") {
                            Exclusions.remove(p)
                            tick += 1
                        }
                    }
                }
            }
        }
    }

    // sejarah

    var historyPanel: some View {
        let list = History.all()
        return Panel {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Sejarah pembersihan").font(.system(size: 15, weight: .semibold))
                    Chip(text: "\(list.count) kali")
                    Spacer()
                }
                if list.isEmpty { Text("Belum ada pembersihan.").font(.system(size: 12.5)).opacity(0.65) }
                ForEach(list.prefix(15)) { h in
                    HStack {
                        Text(h.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 12)).opacity(0.65).frame(width: 150, alignment: .leading)
                        Text(h.note).font(.system(size: 12.5)).lineLimit(1)
                        Spacer()
                        Text("\(h.count) item").font(.system(size: 12)).opacity(0.6)
                        Text(fmt(h.freed)).font(.system(size: 12.5, weight: .semibold)).monospacedDigit().frame(width: 76, alignment: .trailing)
                    }
                }
            }
        }
    }
}
