import AppKit
import SwiftUI

extension Theme {
    static let sims = Theme(id: "sims", a: Color(hex: 0x0E4D5C), b: Color(hex: 0x031A20), glow: Color(hex: 0x22D3EE))
}

struct Confirm: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let label: String
    let run: () -> Void
}

struct SimView: View {
    @EnvironmentObject var sims: SimState
    @State private var confirm: Confirm?

    var grouped: [(name: String, list: [SimDevice])] {
        let dict = Dictionary(grouping: sims.devices, by: { $0.runtimeName })
        return dict.map { (name: $0.key, list: $0.value.sorted { ($0.size ?? 0) > ($1.size ?? 0) }) }
            .sorted { $0.list.reduce(0) { $0 + ($1.size ?? 0) } > $1.list.reduce(0) { $0 + ($1.size ?? 0) } }
    }

    var total: Int64 { sims.devicesSize + sims.runtimesSize }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(icon: "iphone.gen3", title: "Simulator",
                          subtitle: "Data peranti dan runtime iOS. Biasanya yang paling besar di Mac developer.",
                          glow: Theme.sims.glow,
                          trailing: sims.devices.isEmpty ? nil : (sims.sizesReady ? fmt(total) : "Mengira saiz"),
                          trailingNote: sims.devices.isEmpty ? nil : "\(sims.devices.count) peranti, \(sims.runtimes.count) runtime")
            Group {
                if sims.loading && sims.devices.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large).tint(.white)
                        Text("Membaca simulator").font(.system(size: 14)).opacity(0.7)
                    }
                } else if sims.loaded && sims.devices.isEmpty && sims.runtimes.isEmpty {
                    Text("Xcode simulator tak dijumpai.").font(.system(size: 14)).opacity(0.7)
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            runtimesPanel
                            ForEach(grouped, id: \.name) { g in devicePanel(g.name, g.list) }
                        }
                        .padding(.horizontal, 32)
                        .padding(.bottom, 16)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            bottom
        }
        .onAppear { if !sims.loaded { sims.refresh() } }
        .alert(confirm?.title ?? "", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })) {
            if let c = confirm {
                Button("Batal", role: .cancel) {}
                Button(c.label, role: .destructive) { c.run() }
            }
        } message: {
            Text(confirm?.message ?? "")
        }
    }

    var runtimesPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Runtime").font(.system(size: 15, weight: .semibold))
                    Chip(text: fmt(sims.runtimesSize))
                    Spacer()
                    Text("Boleh dimuat turun semula dari Xcode").font(.system(size: 11.5)).opacity(0.55)
                }
                if sims.runtimes.isEmpty { Text("Tiada runtime berasingan.").font(.system(size: 13)).opacity(0.65) }
                ForEach(sims.runtimes) { r in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.name).font(.system(size: 13.5, weight: .semibold))
                            Text("Build \(r.build) · \(r.devices) peranti menggunakannya").font(.system(size: 11.5)).opacity(0.6)
                        }
                        Spacer()
                        Text(fmt(r.size)).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                        IconButton(icon: "trash", help: r.deletable ? "Padam runtime" : "Runtime ini tak boleh dipadam", disabled: !r.deletable || sims.busy) {
                            confirm = Confirm(title: "Padam runtime \(r.name)?",
                                              message: "\(fmt(r.size)) dibebaskan. \(r.devices) peranti yang menggunakannya tak boleh dihidupkan sehingga runtime dimuat turun semula dari Xcode.",
                                              label: "Padam") { sims.deleteRuntime(r) }
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    func devicePanel(_ name: String, _ list: [SimDevice]) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(name).font(.system(size: 15, weight: .semibold))
                    Chip(text: "\(list.count) peranti")
                    Chip(text: list.contains { $0.size == nil } ? "..." : fmt(list.reduce(0) { $0 + ($1.size ?? 0) }))
                    Spacer()
                }
                ForEach(list) { d in
                    HStack(spacing: 12) {
                        Circle().fill(d.booted ? okColor : (d.available ? Color.white.opacity(0.3) : badColor)).frame(width: 9, height: 9)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.name).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                            Text(d.booted ? "Hidup, matikan dulu untuk erase atau padam" : (d.available ? "Dimatikan" : "Tak tersedia, runtime hilang"))
                                .font(.system(size: 11.5)).opacity(0.6)
                        }
                        Spacer()
                        Text(d.size.map(fmt) ?? "...").font(.system(size: 13, weight: .semibold)).monospacedDigit().frame(width: 74, alignment: .trailing)
                        IconButton(icon: "arrow.counterclockwise", help: "Erase: kosongkan app dan data, peranti kekal", disabled: d.booted || !d.available || sims.busy) {
                            confirm = Confirm(title: "Erase \(d.name)?",
                                              message: "Semua app, login dan data dalam simulator ini dipadam. Peranti kekal dan boleh digunakan semula.",
                                              label: "Erase") { sims.erase(d) }
                        }
                        IconButton(icon: "trash", help: "Padam peranti", disabled: d.booted || sims.busy) {
                            confirm = Confirm(title: "Padam \(d.name)?",
                                              message: "Peranti dan semua datanya dibuang. Ini tak boleh dipulihkan.",
                                              label: "Padam") { sims.delete(d) }
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    var bottom: some View {
        HStack(spacing: 10) {
            if sims.busy {
                ProgressView().controlSize(.small).tint(.white)
                Text("Sedang berjalan").font(.system(size: 12.5)).opacity(0.8)
            } else if let m = sims.message {
                Text(m).font(.system(size: 12.5)).opacity(0.85).lineLimit(2)
            }
            Spacer()
            IconButton(icon: "arrow.clockwise", help: "Imbas semula", disabled: sims.loading || sims.busy) { sims.refresh() }
            if sims.bootedCount > 0 {
                PillButton(title: "Matikan \(sims.bootedCount) yang hidup", icon: "power", filled: false) { sims.shutdownAll() }
                    .disabled(sims.busy)
            }
            if !sims.unavailable.isEmpty {
                PillButton(title: "Padam \(sims.unavailable.count) tak tersedia", icon: "trash", filled: false) {
                    confirm = Confirm(title: "Padam \(sims.unavailable.count) peranti tak tersedia?",
                                      message: "Peranti ini rosak kerana runtime dah tiada. Datanya dibuang.", label: "Padam") { sims.deleteUnavailable() }
                }
                .disabled(sims.busy)
            }
            let e = sims.erasable
            PillButton(title: e.isEmpty ? "Tiada untuk erase" : "Erase \(e.count) simulator" + (sims.sizesReady ? " (\(fmt(e.reduce(0) { $0 + ($1.size ?? 0) })))" : ""),
                       icon: "sparkles", filled: true, tint: Theme.sims.a) {
                confirm = Confirm(title: "Erase \(e.count) simulator?",
                                  message: "Semua app, login dan data dalam simulator yang dimatikan dipadam. Peranti kekal. \(sims.bootedCount) yang hidup tak disentuh.",
                                  label: "Erase semua") { sims.eraseAllShutdown() }
            }
            .disabled(e.isEmpty || sims.busy)
            .opacity(e.isEmpty || sims.busy ? 0.5 : 1)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
        .background(Color.black.opacity(0.22))
    }
}
