import AppKit
import SwiftUI

/// Two interface languages: Bahasa Melayu (the source text) and English.
/// Text is written in Malay in the source; `tr` maps it to English at display time,
/// so stored data (history, scan cache) never changes with the language.
final class Lang: ObservableObject {
    static let shared = Lang()
    static let key = "hsapu.lang"
    @Published var code: String { didSet { UserDefaults.standard.set(code, forKey: Lang.key); Lang.cache = [:] } }
    static var cache: [String: String] = [:]
    init() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--lang"), i + 1 < args.count, args[i + 1] == "ms" || args[i + 1] == "en" { code = args[i + 1] }
        else if let c = UserDefaults.standard.string(forKey: Lang.key), c == "ms" || c == "en" { code = c } else { code = "ms" }
    }
    static var isEnglish: Bool { shared.code == "en" }
    static var locale: Locale { Locale(identifier: isEnglish ? "en_MY" : "ms_MY") }

    private static let exact: [String: String] = {
        var d = [String: String]()
        for (k, v) in pairs where !k.contains("{") { d[k] = v }
        return d
    }()
    private static let patterns: [(NSRegularExpression, String)] = pairs.filter { $0.0.contains("{") }.compactMap { k, v in
        var rx = "^"; var rest = Substring(k)
        while let r = rest.range(of: #"\{\d+\}"#, options: .regularExpression) {
            rx += NSRegularExpression.escapedPattern(for: String(rest[..<r.lowerBound])) + "(.+?)"
            rest = rest[r.upperBound...]
        }
        rx += NSRegularExpression.escapedPattern(for: String(rest)) + "$"
        guard let re = try? NSRegularExpression(options: [], pattern: rx, options: [.dotMatchesLineSeparators]) else { return nil }
        return (re, v)
    }

    static func translate(_ s: String) -> String {
        if let c = cache[s] { return c }
        var out = s
        if let e = exact[s] { out = e } else {
            let ns = s as NSString
            for (re, tpl) in patterns {
                guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { continue }
                var t = tpl
                for i in 1..<m.numberOfRanges { t = t.replacingOccurrences(of: "{\(i)}", with: translate(ns.substring(with: m.range(at: i)))) }
                out = t; break
            }
            if out == s, s.contains(" · ") {
                out = s.components(separatedBy: " · ").map { translate($0) }.joined(separator: " · ")
            }
        }
        cache[s] = out
        return out
    }
}

private extension NSRegularExpression {
    convenience init?(options: [Int], pattern: String, options o: NSRegularExpression.Options) { try? self.init(pattern: pattern, options: o) }
}

func tr(_ s: String) -> String { Lang.isEnglish ? Lang.translate(s) : s }

// Every plain String shown through these views goes through `tr`.
extension Text {
    init(_ s: String) { self.init(verbatim: tr(s)) }
}
extension Button where Label == Text {
    init(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) { self.init(role: role, action: action) { Text(verbatim: tr(title)) } }
}
extension Toggle where Label == Text {
    init(_ title: String, isOn: Binding<Bool>) { self.init(isOn: isOn) { Text(verbatim: tr(title)) } }
}
extension Stepper where Label == Text {
    init(_ title: String, value: Binding<Int>, in range: ClosedRange<Int>, step: Int = 1) { self.init(value: value, in: range, step: step) { Text(verbatim: tr(title)) } }
}
extension View {
    func help(_ s: String) -> some View { self.help(Text(verbatim: tr(s))) }
}

private let pairs: [(String, String)] = [
    ("Semua kategori", "All categories"),
    ("Pembersih (ke Tong Sampah)", "Cleaner (to Trash)"),
    ("Pembersih", "Cleaner"),
    ("Ruang cakera rendah", "Low disk space"),
    ("Tinggal {1}. Buka HSapu untuk bersihkan.", "{1} left. Open HSapu to clean up."),
    ("HSapu jumpa {1} boleh dibersihkan", "HSapu found {1} you can clean"),
    ("Buka HSapu untuk semak dan bersihkan.", "Open HSapu to review and clean."),
    ("Cache Gradle", "Gradle cache"),
    ("Cache developer", "Developer caches"),
    ("Worktree git", "Git worktrees"),
    ("Dipadam terus", "Deleted permanently"),
    ("Worktree", "Worktrees"),
    ("{1}: {2} item tak dapat dipadam", "{1}: {2} items could not be deleted"),
    ("{1}: {2} fail tak dapat dialih", "{1}: {2} files could not be moved"),
    ("7 hari", "7 days"), ("30 hari", "30 days"), ("90 hari", "90 days"), ("Semua", "All"),
    ("Hari ini · ", "Today · "), ("Semalam · ", "Yesterday · "),
    ("Sejarah", "History"),
    ("Apa yang dibersihkan, bila, dan berapa GB.", "What was cleaned, when, and how many GB."),
    ("dibebaskan dalam {1}", "freed in {1}"),
    ("pada tarikh dipilih", "on the chosen date"),
    ("Belum ada sejarah", "No history yet"),
    ("Setiap pembersihan, buang worktree dan tindakan simulator akan direkod di sini.", "Every clean-up, worktree removal and simulator action is recorded here."),
    ("Tarikh tertentu", "Specific date"), ("Semua tarikh", "All dates"),
    ("{1} dipadam pada {2}", "{1} deleted on {2}"),
    ("Tiada pembersihan pada {1}", "No clean-up on {1}"),
    ("GB dibebaskan setiap hari", "GB freed each day"),
    ("Hari", "Day"),
    ("{1} tindakan · {2} item", "{1} actions · {2} items"),
    ("{1} item", "{1} items"),
    ("dan {1} lagi", "and {1} more"),
    ("Rekod lama: butiran item tak disimpan.", "Older record: item details were not saved."),
    ("iOS asli", "Native iOS"),
    ("Naikkan nombor build atau versionCode", "Raise the build number or versionCode"),
    ("Build di CI lulus", "CI build passes"),
    ("Diuji pada peranti sebenar", "Tested on a real device"),
    ("Nota keluaran siap", "Release notes ready"),
    ("Dihantar ke TestFlight atau Play Console", "Submitted to TestFlight or Play Console"),
    ("Worktree dibuang, branch kekal", "Worktree removed, branch kept"),
    ("{1} worktree dibuang. Branch kekal.", "{1} worktrees removed. Branches kept."),
    ("tarikh tak diketahui", "date unknown"),
    ("baru sebentar tadi", "just now"),
    ("Perlu perhatian", "Needs attention"), ("Dah merge", "Merged"), ("Belum merge", "Not merged"),
    ("Semua repo", "All repos"),
    ("Worktree dan sesi", "Worktrees and sessions"),
    ("Semua git worktree merentas projek kau, dengan status sebenar.", "Every git worktree across your projects, with its real status."),
    ("Mengira saiz", "Calculating sizes"),
    ("{1} worktree", "{1} worktrees"),
    ("Membaca status git", "Reading git status"),
    ("Tiada worktree dalam paparan ini.", "No worktrees in this view."),
    ("Buang {1} worktree?", "Remove {1} worktrees?"),
    ("Batal", "Cancel"), ("Buang", "Remove"),
    ("Semuanya dah merge dan bersih. Folder dibuang, branch kekal dalam repo.", "All merged and clean. The folders are removed, the branches stay in the repo."),
    ("Buang worktree ini?", "Remove this worktree?"),
    ("{1} dalam {2}. Branch kekal dalam repo.", "{1} in {2}. The branch stays in the repo."),
    ("Imbas semula", "Rescan"),
    ("Buka di Terminal", "Open in Terminal"), ("Buka di editor", "Open in editor"), ("Tunjuk di Finder", "Show in Finder"),
    ("Buang worktree", "Remove worktree"),
    ("Ada kerja belum selamat, tak boleh dibuang", "Has unsaved work, cannot be removed"),
    ("Jangan sentuh worktree ini", "Do not touch this worktree"),
    ("bukan worktree git yang sah", "not a valid git worktree"),
    ("{1} fail belum commit", "{1} uncommitted files"),
    ("{1} commit belum push", "{1} unpushed commits"),
    ("dah merge", "merged"),
    ("Tiada yang dah merge", "Nothing merged"),
    ("Buang {1} yang dah merge", "Remove {1} merged"),
    ("Build dan release", "Builds and releases"),
    ("Versi dan nombor build setiap app, status CI dan senarai semak sebelum submit.", "Version and build number of every app, CI status and a checklist before you submit."),
    ("{1} app", "{1} apps"),
    ("Mencari app dalam projek kau", "Finding apps in your projects"),
    ("Tiada app dijumpai.", "No apps found."),
    ("CI tiada data", "CI no data"), ("CI lulus", "CI passed"), ("CI gagal", "CI failed"), ("CI sedang jalan", "CI running"), ("CI dibatalkan", "CI cancelled"),
    ("bundle id tak dijumpai", "bundle id not found"),
    ("Versi", "Version"), ("iOS build", "iOS build"), ("Android code", "Android code"),
    ("Commit terakhir", "Last commit"),
    ("Larian CI terakhir: ", "Last CI run: "),
    ("Senarai semak {1}/{2}", "Checklist {1}/{2}"),
    ("Buka repo di GitHub", "Open repo on GitHub"),
    ("Set semula senarai semak", "Reset checklist"),
    ("Docker, simulator, emulator dan ruang disk di satu tempat.", "Docker, simulators, emulators and disk space in one place."),
    ("{1} kosong", "{1} free"),
    ("daripada {1}", "of {1}"),
    ("Ruang disk tinggal kurang {1} GB. Buka Pembersih untuk bebaskan ruang.", "Less than {1} GB of disk space left. Open the Cleaner to free some."),
    ("Buka Pembersih", "Open Cleaner"),
    ("Docker tak dipasang.", "Docker is not installed."),
    ("Berjalan", "Running"),
    ("{1} container aktif, {2} kesemuanya.", "{1} containers active, {2} in total."),
    ("Tak berjalan", "Not running"),
    ("Buka Docker", "Open Docker"),
    ("Simulator dan emulator", "Simulators and emulators"),
    ("{1} simulator iOS hidup", "{1} iOS simulators running"),
    ("Simulator yang hidup makan RAM dan bateri.", "Running simulators use RAM and battery."),
    ("Matikan semua", "Shut all down"),
    ("{1} emulator Android hidup, {2} AVD", "{1} Android emulators running, {2} AVDs"),
    ("Tiada AVD", "No AVDs"),
    ("Docker berjalan, {1} container aktif", "Docker is running, {1} containers active"),
    ("Docker tak berjalan", "Docker is not running"),
    ("Worktree belum diimbas", "Worktrees not scanned yet"),
    ("{1} worktree perlu perhatian, {2} boleh dibuang", "{1} worktrees need attention, {2} can be removed"),
    ("{1} app dijejak", "{1} apps tracked"),
    ("{1} simulator hidup", "{1} simulators running"),
    ("HSapu {1} tersedia", "HSapu {1} available"),
    ("Buka HSapu", "Open HSapu"),
    ("Keluar", "Quit"),
    ("Pemasang", "Installers"), ("Arkib", "Archives"), ("Video", "Video"), ("Gambar", "Images"), ("Audio", "Audio"),
    ("Dokumen", "Documents"), ("Kod dan data", "Code and data"), ("Folder", "Folders"), ("Lain", "Other"),
    ("Saiz", "Size"), ("Tarikh ditambah", "Date added"), ("Terakhir digunakan", "Last used"), ("Nama", "Name"),
    ("Sampah sistem", "System junk"),
    ("Cache aplikasi, log dan Tong Sampah.", "App caches, logs and the Trash."),
    ("Fail build, simbol peranti dan data simulator.", "Build files, device symbols and simulator data."),
    ("Gradle, npm, model AI dan emulator Android.", "Gradle, npm, AI models and Android emulators."),
    ("Boleh dipasang semula dengan npm install.", "Can be reinstalled with npm install."),
    ("Salinan projek daripada sesi Claude Code dan git worktree lain.", "Project copies from Claude Code sessions and other git worktrees."),
    ("Folder home", "Home folder"),
    ("Folder besar dalam folder pengguna, sandaran lama dan data alat.", "Large folders in your user folder, old backups and tool data."),
    ("Pemasang, pendua dan fail lama dalam folder Downloads.", "Installers, duplicates and old files in the Downloads folder."),
    ("Fail besar", "Large files"),
    ("Fail melebihi 300 MB dalam Desktop, Documents dan Movies.", "Files over 300 MB in Desktop, Documents and Movies."),
    ("Cache aplikasi, dibina semula bila perlu", "App caches, rebuilt when needed"),
    ("Log aplikasi", "App logs"),
    ("Tong Sampah", "Trash"),
    ("Kosongkan terus", "Empty it"),
    ("Cache build, dibina semula pada build seterusnya", "Build cache, rebuilt on the next build"),
    ("Simbol peranti, dimuat turun semula bila sambung", "Device symbols, downloaded again when you connect"),
    ("Cache simulator", "Simulator cache"), ("Cache dyld simulator", "Simulator dyld cache"),
    ("Mengandungi dSYM untuk crash report", "Contains dSYMs for crash reports"),
    ("Data semua simulator", "All simulator data"),
    ("App dan login dalam simulator hilang. Saiz ialah anggaran.", "Apps and logins inside the simulators are lost. Size is an estimate."),
    ("Dimuat turun semula pada build Android", "Downloaded again on the next Android build"),
    ("Cache pakej npm", "npm package cache"), ("Cache pakej Yarn", "Yarn package cache"),
    ("Pakej Flutter dan Dart", "Flutter and Dart packages"), ("Pakej Rust", "Rust packages"),
    ("Spec repo CocoaPods", "CocoaPods spec repo"),
    ("Sesi Codex", "Codex sessions"), ("Sejarah sesi Codex lama", "Old Codex session history"),
    ("Cache dalam ~/.cache", "Cache in ~/.cache"),
    ("Emulator Android, perlu dicipta semula", "Android emulator, must be created again"),
    ("Jalankan npm install untuk pasang semula", "Run npm install to reinstall"),
    ("Bukan worktree git yang sah", "Not a valid git worktree"),
    ("Dah merge, bersih", "Merged, clean"), ("Belum merge, bersih", "Not merged, clean"),
    ("Data Claude Code", "Claude Code data"), ("Sejarah sesi Claude Code untuk projek ini", "Claude Code session history for this project"),
    ("Data Codex", "Codex data"),
    ("Projek git, tak disentuh. Lihat Worktree git dan node_modules untuk bahagian yang boleh dibuang.", "Git project, left alone. See Git worktrees and node_modules for the parts you can remove."),
    ("Mengandungi git worktree. Buang melalui kategori Worktree git.", "Contains git worktrees. Remove them through the Git worktrees category."),
    ("{1}: sandaran lama", "{1}: old backups"),
    ("{1} fail lama, 7 terbaru dikekalkan · dialih ke Tong Sampah", "{1} old files, newest 7 kept · moved to Trash"),
    ("Cache penganalisis Dart, dibina semula", "Dart analyzer cache, rebuilt"),
    ("Cache dan tetapan Expo", "Expo cache and settings"),
    ("Persekitaran Python, boleh dicipta semula", "Python environment, can be recreated"),
    ("Runner GitHub Actions. Jangan buang kalau CI masih guna", "GitHub Actions runner. Do not remove if CI still uses it"),
    ("Data alat {1}", "{1} tool data"),
    ("Fail", "File"),
    (" · diubah {1}", " · modified {1}"),
    (" · dialih ke Tong Sampah", " · moved to Trash"),
    ("Sesi Claude: ", "Claude session: "),
    ("Muat turun tak lengkap", "Incomplete download"),
    ("Fail pemasang, tak perlu selepas dipasang", "Installer file, not needed once installed"),
    ("Arkib yang dah diekstrak ke folder {1}", "Archive already extracted to the folder {1}"),
    ("Pendua kepada {1}", "Duplicate of {1}"),
    (" · lama tak disentuh", " · untouched for a long time"),
    ("Dikosongkan terus", "Emptied"), ("Ke Tong Sampah", "To Trash"),
    ("Semua simulator di-erase", "All simulators erased"),
    ("Bersihkan {1} item?", "Clean {1} items?"),
    ("{1} daripada {2}. Semak senarai dulu.", "{1} from {2}. Review the list first."),
    ("Alih ke Tong Sampah, bukannya padam terus", "Move to Trash instead of deleting permanently"),
    ("Boleh dipulihkan, tapi ruang hanya bebas selepas Tong Sampah dikosongkan.", "Can be restored, but space is only freed once the Trash is emptied."),
    ("Alih {1}", "Move {1}"), ("Bersihkan {1}", "Clean {1}"),
    ("Tetapan", "Settings"),
    ("Kemas kini, pemantauan, kecualian dan sejarah.", "Updates, monitoring, exclusions and history."),
    ("dibebaskan sepanjang masa", "freed all time"),
    ("Versi {1}", "Version {1}"),
    ("Pembersih Mac dan hab kerja untuk developer.", "Mac cleaner and workspace hub for developers."),
    ("Pembangun", "Developer"), ("Laman pembangun", "Developer website"), ("Hubungi", "Contact"),
    ("Laman HSapu", "HSapu website"), ("Keluaran", "Releases"), ("Maklum balas", "Feedback"),
    ("Lapor isu atau idea", "Report an issue or idea"),
    ("Kemas kini", "Updates"), ("Menyemak", "Checking"), ("Semak sekarang", "Check now"),
    ("Versi {1} tersedia.", "Version {1} is available."),
    ("HSapu dah versi terkini.", "HSapu is up to date."),
    ("Versi {1} tersedia", "Version {1} is available"),
    ("Memasang", "Installing"), ("Muat turun dan pasang", "Download and install"),
    ("HSapu dikemas kini dan akan dibuka semula.", "HSapu was updated and will reopen."),
    ("Semak kemas kini sekali sehari", "Check for updates once a day"),
    ("Kemas kini dimuat turun dari keluaran awam di GitHub (terascoremy/HSapu), disahkan dengan checksum sebelum dipasang.", "Updates are downloaded from the public releases on GitHub (terascoremy/HSapu) and verified with a checksum before they are installed."),
    ("Pemantauan", "Monitoring"),
    ("Beritahu bila ruang cakera kurang daripada", "Notify me when free disk space drops below"),
    ("Imbas automatik di latar", "Automatic scan in the background"),
    ("Mati", "Off"), ("Setiap hari", "Every day"), ("Setiap minggu", "Every week"),
    ("Buka HSapu semasa log masuk", "Open HSapu at login"),
    ("Notifikasi disekat. Benarkan HSapu dalam Tetapan Sistem > Notifikasi.", "Notifications are blocked. Allow HSapu in System Settings > Notifications."),
    ("Pemantauan hanya berjalan selagi HSapu dibuka (ikon di bar menu).", "Monitoring only runs while HSapu is open (icon in the menu bar)."),
    ("Notifikasi hanya berfungsi bila HSapu dibuka sebagai app (.app), bukan dari terminal.", "Notifications only work when HSapu is opened as an app (.app), not from the terminal."),
    ("Akses Cakera Penuh", "Full Disk Access"),
    ("Aktif", "Active"), ("Tiada", "None"), ("Tak pasti", "Unknown"),
    ("Tanpa ini HSapu tak dapat mengimbas folder dilindungi macOS (Safari, Mail, Messages). Folder lain berfungsi seperti biasa.", "Without it HSapu cannot scan folders protected by macOS (Safari, Mail, Messages). Other folders work as usual."),
    ("Membolehkan HSapu mengimbas folder dilindungi macOS.", "Lets HSapu scan folders protected by macOS."),
    ("Buka Tetapan", "Open Settings"), ("Semak semula", "Check again"),
    ("Jangan sentuh", "Do not touch"),
    ("Klik kanan mana-mana item dalam pembersih dan pilih \"Jangan sentuh\" untuk tambah di sini. Item ini tak akan muncul atau dipadam.", "Right-click any item in the cleaner and choose \"Do not touch\" to add it here. These items never show up and are never deleted."),
    ("Benarkan semula (imbas semula untuk nampak)", "Allow again (rescan to see it)"),
    ("Sejarah pembersihan", "Clean-up history"),
    ("Belum ada pembersihan.", "No clean-ups yet."),
    ("{1} pembersihan, {2} dibebaskan sepanjang masa.", "{1} clean-ups, {2} freed all time."),
    ("Buka sejarah", "Open history"),
    ("Booted", "Running"), ("Booting", "Starting"), ("Shutdown", "Off"),
    ("{1} siap", "{1} done"),
    (", {1} dibebaskan.", ", {1} freed."),
    ("Simulator: {1}", "Simulator: {1}"),
    ("Erase {1}", "Erase {1}"), ("Di-erase", "Erased"),
    ("Padam {1}", "Delete {1}"), ("Peranti dipadam", "Device deleted"),
    ("Erase {1} simulator", "Erase {1} simulators"),
    ("Padam peranti tak tersedia", "Delete unavailable devices"),
    ("Peranti tak tersedia dipadam", "Unavailable devices deleted"),
    ("Semua simulator dimatikan.", "All simulators shut down."),
    ("Padam runtime {1}", "Delete runtime {1}"), ("Runtime dipadam", "Runtime deleted"),
    ("Data peranti dan runtime iOS. Biasanya yang paling besar di Mac developer.", "iOS device data and runtimes. Usually the biggest thing on a developer Mac."),
    ("{1} peranti, {2} runtime", "{1} devices, {2} runtimes"),
    ("Membaca simulator", "Reading simulators"),
    ("Xcode simulator tak dijumpai.", "Xcode simulator not found."),
    ("Boleh dimuat turun semula dari Xcode", "Can be downloaded again from Xcode"),
    ("Tiada runtime berasingan.", "No separate runtimes."),
    ("Build {1} · {2} peranti menggunakannya", "Build {1} · used by {2} devices"),
    ("Padam runtime", "Delete runtime"),
    ("Runtime ini tak boleh dipadam", "This runtime cannot be deleted"),
    ("Padam runtime {1}?", "Delete runtime {1}?"),
    ("{1} dibebaskan. {2} peranti yang menggunakannya tak boleh dihidupkan sehingga runtime dimuat turun semula dari Xcode.", "{1} freed. The {2} devices that use it cannot be started until the runtime is downloaded again from Xcode."),
    ("Padam", "Delete"),
    ("{1} peranti", "{1} devices"),
    ("Hidup, matikan dulu untuk erase atau padam", "Running, shut it down first to erase or delete"),
    ("Dimatikan", "Shut down"),
    ("Tak tersedia, runtime hilang", "Unavailable, runtime missing"),
    ("Erase: kosongkan app dan data, peranti kekal", "Erase: clears apps and data, the device stays"),
    ("Erase {1}?", "Erase {1}?"),
    ("Semua app, login dan data dalam simulator ini dipadam. Peranti kekal dan boleh digunakan semula.", "All apps, logins and data in this simulator are deleted. The device stays and can be used again."),
    ("Erase", "Erase"), ("Padam peranti", "Delete device"),
    ("Padam {1}?", "Delete {1}?"),
    ("Peranti dan semua datanya dibuang. Ini tak boleh dipulihkan.", "The device and all of its data are removed. This cannot be undone."),
    ("Sedang berjalan", "In progress"),
    ("Matikan {1} yang hidup", "Shut down {1} running"),
    ("Padam {1} tak tersedia", "Delete {1} unavailable"),
    ("Padam {1} peranti tak tersedia?", "Delete {1} unavailable devices?"),
    ("Peranti ini rosak kerana runtime dah tiada. Datanya dibuang.", "These devices are broken because their runtime is gone. Their data is removed."),
    ("Tiada untuk erase", "Nothing to erase"),
    ("Erase {1} simulator?", "Erase {1} simulators?"),
    ("Semua app, login dan data dalam simulator yang dimatikan dipadam. Peranti kekal. {1} yang hidup tak disentuh.", "All apps, logins and data in the shut down simulators are deleted. The devices stay. {1} running are left alone."),
    ("Erase semua", "Erase all"),
    ("Ada item tak dapat dibersihkan", "Some items could not be cleaned"),
    ("Ringkasan pembersih", "Cleaner overview"), ("Kerja", "Work"),
    ("{1} perhatian", "{1} need attention"),
    ("{1} sim hidup", "{1} sims running"),
    ("Pembersihan", "Cleaning"),
    ("Sedang mengimbas", "Scanning"),
    ("{1} dialih ke Tong Sampah", "{1} moved to Trash"),
    ("{1} dibebaskan", "{1} freed"),
    ("{1} dijumpai", "{1} found"),
    ("Mac ni dah kemas", "Your Mac is tidy"),
    ("Jom kemas Mac ni", "Let's tidy your Mac"),
    ("{1} daripada {2} kategori siap.", "{1} of {2} categories done."),
    ("Mengemas kini di latar. Hasil imbasan terakhir dipaparkan dulu.", "Updating in the background. The last scan result is shown first."),
    ("Kosongkan Tong Sampah untuk bebaskan ruang sebenar.", "Empty the Trash to free real space."),
    ("{1} dah dipilih sebab selamat dibuang. Buka kategori untuk pilih yang lain.", "{1} already chosen because it is safe to remove. Open a category to choose others."),
    ("Tiada yang dipilih. Buka kategori untuk pilih item.", "Nothing chosen. Open a category to choose items."),
    ("Imbas untuk cari cache, fail build, worktree lama dan fail besar.", "Scan to find caches, build files, old worktrees and large files."),
    ("Imbasan terakhir {1}", "Last scan {1}"),
    (" · {1} dibebaskan sepanjang masa", " · {1} freed all time"),
    ("Mengimbas", "Scanning"), ("Tiada pilihan", "No selection"), ("Bersih", "Clean"),
    ("Belum diimbas", "Not scanned yet"), ("Imbas", "Scan"),
    ("Tiada apa untuk dibuang di sini.", "Nothing to remove here."),
    ("Imbas dulu untuk lihat apa yang boleh dibuang.", "Scan first to see what can be removed."),
    ("Imbas sekarang", "Scan now"),
    ("Selamat", "Safe"), ("Semak dulu", "Review"), ("Dikunci", "Locked"),
    ("Cari nama", "Search name"), ("Isih", "Sort"), ("Isih: ", "Sort: "), ("Umur", "Age"), ("Semua umur", "Any age"),
    ("Tak digunakan > 30 hari", "Unused > 30 days"), ("Tak digunakan > 90 hari", "Unused > 90 days"),
    ("Tak digunakan > 180 hari", "Unused > 180 days"), ("Tak digunakan > 1 tahun", "Unused > 1 year"),
    ("Umur: semua", "Age: any"), ("Tak digunakan > {1} hari", "Unused > {1} days"),
    ("Set semula tapisan", "Reset filters"),
    ("Semua jenis", "All types"),
    ("Tiada item yang sepadan dengan tapisan.", "No items match the filters."),
    ("Pilih yang selamat", "Select the safe ones"),
    ("Pilih semua ({1})", "Select all ({1})"), ("Pilih semua", "Select all"),
    ("Kosongkan", "Clear"),
    ("{1} dipilih", "{1} selected"),
    (" ({1} tersembunyi oleh tapisan)", " ({1} hidden by filters)"),
    ("Bersihkan", "Clean"),
    ("Ditambah ", "Added "), ("Ditambah -", "Added -"), ("Digunakan ", "Used "), ("Digunakan -", "Used -"),
    ("Tunjuk dalam Finder", "Show in Finder"),
    ("Jangan sentuh item ini lagi", "Never touch this item again"),
    ("Sedang membersih", "Cleaning"),
    ("Mengimbas {1} daripada {2} kategori · {3} saat", "Scanning {1} of {2} categories · {3} s"),
    ("Masih berjalan: ", "Still running: "),
    ("Mengimbas {1}/{2}", "Scanning {1}/{2}"),
    ("Bahasa", "Language"),
    ("digunakan", "used"),
    ("{1} dibebaskan sepanjang masa", "{1} freed all time"),
    ("Buang {1} yang dah merge ({2})", "Remove {1} merged ({2})"),
    ("{1} daripada {2} kategori", "{1} of {2} categories"),
    ("Bahasa Melayu", "Bahasa Melayu"),
    ("Pilih bahasa antara muka. Tetapan ini disimpan.", "Choose the interface language. This choice is saved."),
]
