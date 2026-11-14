import Charts
import SwiftUI

enum HistoryRange: Int, CaseIterable {
    case d7 = 7, d30 = 30, d90 = 90, all = 0

    var title: String {
        switch self {
        case .d7: return "7 hari"
        case .d30: return "30 hari"
        case .d90: return "90 hari"
        case .all: return "Semua"
        }
    }

    func cutoff(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard rawValue > 0 else { return nil }
        return calendar.date(byAdding: .day, value: -(rawValue - 1), to: calendar.startOfDay(for: now))
    }
}

func dayTitle(_ d: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "ms_MY")
    f.dateFormat = "EEEE, d MMMM yyyy"
    let base = f.string(from: d)
    if Calendar.current.isDateInToday(d) { return "Hari ini · " + base }
    if Calendar.current.isDateInYesterday(d) { return "Semalam · " + base }
    return base
}

func timeTitle(_ d: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return f.string(from: d)
}

struct HistoryView: View {
    @EnvironmentObject var state: AppState
    @State private var entries: [HistoryEntry] = []
    @State private var range: HistoryRange = .d30
    @State private var picked: Date?
    @State private var expanded: Set<Date> = []
    @State private var firstLoad = true

    var inRange: [HistoryEntry] {
        guard let c = range.cutoff() else { return entries }
        return entries.filter { $0.date >= c }
    }

    var days: [DaySummary] {
        if let p = picked { return History.byDay(entries.filter { Calendar.current.isDate($0.date, inSameDayAs: p) }) }
        return History.byDay(inRange)
    }

    var total: Int64 { days.reduce(0) { $0 + $1.freed } }

    /// Satu bar setiap hari dalam julat, termasuk hari kosong, supaya carta jujur.
    var chartDays: [(day: Date, freed: Int64)] {
        let cal = Calendar.current
        let byDay = Dictionary(uniqueKeysWithValues: History.byDay(inRange).map { ($0.day, $0.freed) })
        guard let start = range.cutoff() else { return byDay.map { ($0.key, $0.value) }.sorted { $0.0 < $1.0 } }
        var out = [(day: Date, freed: Int64)]()
        var d = start
        let end = cal.startOfDay(for: Date())
        while d <= end {
            out.append((d, byDay[d] ?? 0))
            guard let n = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = n
        }
        return out
    }

    func reload() {
        entries = History.all()
        if firstLoad, let first = History.byDay(entries).first { expanded = [first.day] }
        firstLoad = false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(icon: "clock.arrow.circlepath", title: "Sejarah",
                          subtitle: "Apa yang dibersihkan, bila, dan berapa GB.",
                          glow: Theme.overview.glow,
                          trailing: entries.isEmpty ? nil : fmt(total),
                          trailingNote: entries.isEmpty ? nil : (picked == nil ? "dibebaskan dalam \(range.title.lowercased())" : "pada tarikh dipilih"))
            if entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock").font(.system(size: 40, weight: .semibold)).opacity(0.9)
                    Text("Belum ada sejarah").font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("Setiap pembersihan, buang worktree dan tindakan simulator akan direkod di sini.").font(.system(size: 13)).opacity(0.7)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                controls
                ScrollView {
                    VStack(spacing: 14) {
                        if picked == nil && range != .all { chartPanel }
                        if let p = picked { pickedSummary(p) }
                        ForEach(days) { d in dayPanel(d) }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
                }
            }
        }
        .onAppear { reload() }
        .onChange(of: state.lastFreed) { _ in reload() }
        .onChange(of: state.cleaning) { _ in reload() }
    }

    // kawalan

    var controls: some View {
        HStack(spacing: 8) {
            ForEach(HistoryRange.allCases, id: \.rawValue) { r in
                FilterChip(title: r.title, count: entries.filter { e in r.cutoff().map { e.date >= $0 } ?? true }.count,
                           selected: picked == nil && range == r) {
                    picked = nil
                    range = r
                }
            }
            Spacer()
            Text("Tarikh tertentu").font(.system(size: 12.5)).opacity(0.7)
            DatePicker("", selection: Binding(get: { picked ?? Date() }, set: { picked = Calendar.current.startOfDay(for: $0) }),
                       in: ...Date(), displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
                .colorScheme(.dark)
            if picked != nil {
                PillButton(title: "Semua tarikh", icon: "xmark", filled: false) { picked = nil }
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 12)
    }

    func pickedSummary(_ day: Date) -> some View {
        Panel {
            HStack(spacing: 12) {
                Image(systemName: "calendar").font(.system(size: 20))
                if total > 0 {
                    Text("\(fmt(total)) dipadam pada \(dayTitle(day))").font(.system(size: 15, weight: .semibold))
                } else {
                    Text("Tiada pembersihan pada \(dayTitle(day))").font(.system(size: 15, weight: .semibold))
                }
                Spacer()
            }
        }
    }

    // carta

    var chartPanel: some View {
        let data = chartDays
        return Panel {
            VStack(alignment: .leading, spacing: 8) {
                Text("GB dibebaskan setiap hari").font(.system(size: 15, weight: .semibold))
                Chart {
                    ForEach(data, id: \.day) { d in
                        BarMark(x: .value("Hari", d.day, unit: .day), y: .value("GB", Double(d.freed) / 1_000_000_000))
                            .foregroundStyle(d.freed > 0 ? Color.white.opacity(0.9) : Color.white.opacity(0.15))
                            .cornerRadius(3)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 7)) { _ in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated)).foregroundStyle(Color.white.opacity(0.7))
                    }
                }
                .chartYAxis {
                    AxisMarks { v in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.1))
                        AxisValueLabel {
                            if let g = v.as(Double.self) { Text("\(Int(g)) GB").foregroundStyle(Color.white.opacity(0.7)) }
                        }
                    }
                }
                .frame(height: 170)
            }
        }
    }

    // hari

    func dayPanel(_ d: DaySummary) -> some View {
        let open = expanded.contains(d.day) || picked != nil
        return Panel {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    if expanded.contains(d.day) { expanded.remove(d.day) } else { expanded.insert(d.day) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 11, weight: .bold)).frame(width: 14).opacity(0.6)
                        Text(dayTitle(d.day)).font(.system(size: 14.5, weight: .semibold))
                        Spacer()
                        Text("\(d.entries.count) tindakan · \(d.count) item").font(.system(size: 12)).opacity(0.6)
                        Text(fmt(d.freed)).font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit().frame(width: 90, alignment: .trailing)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if open {
                    ForEach(d.entries.sorted { $0.date > $1.date }) { e in entryView(e) }
                }
            }
        }
    }

    func entryView(_ e: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(timeTitle(e.date)).font(.system(size: 12, weight: .medium)).monospacedDigit().opacity(0.6).frame(width: 42, alignment: .leading)
                Text(e.note).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(e.count) item").font(.system(size: 12)).opacity(0.6)
                Text(fmt(e.freed)).font(.system(size: 13, weight: .semibold)).monospacedDigit().frame(width: 90, alignment: .trailing)
            }
            if let items = e.items, !items.isEmpty {
                ForEach(Array(items.sorted { $0.size > $1.size }.prefix(40).enumerated()), id: \.offset) { _, it in
                    HStack(spacing: 8) {
                        Text(it.name).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                        Chip(text: it.category)
                        Text(it.how).font(.system(size: 11.5)).opacity(0.55).lineLimit(1)
                        Spacer(minLength: 6)
                        Text(fmt(it.size)).font(.system(size: 12)).monospacedDigit().opacity(0.85).frame(width: 90, alignment: .trailing)
                    }
                    .padding(.leading, 52)
                }
                if items.count > 40 {
                    Text("dan \(items.count - 40) lagi").font(.system(size: 11.5)).opacity(0.5).padding(.leading, 52)
                }
            } else {
                Text("Rekod lama: butiran item tak disimpan.").font(.system(size: 11.5)).opacity(0.5).padding(.leading, 52)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
    }
}
