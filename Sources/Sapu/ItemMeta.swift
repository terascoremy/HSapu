import CoreServices
import Foundation

/// Jenis, tarikh ditambah dan tarikh terakhir digunakan untuk setiap item, supaya boleh ditapis dan diisih.
enum ItemMeta {
    static let groups: [String: [String]] = [
        "Pemasang": ["dmg", "pkg", "mpkg", "app", "exe", "msi", "apk", "ipa"],
        "Arkib": ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "iso"],
        "Video": ["mov", "mp4", "m4v", "avi", "mkv", "webm", "mts"],
        "Gambar": ["png", "jpg", "jpeg", "heic", "gif", "webp", "tiff", "bmp", "raw", "svg", "psd", "ai"],
        "Audio": ["mp3", "m4a", "wav", "aac", "flac", "aiff"],
        "Dokumen": ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "txt", "rtf", "csv", "md", "epub"],
        "Kod dan data": ["json", "js", "ts", "swift", "py", "sql", "db", "sqlite", "log", "xml", "yaml", "yml", "html", "css", "dart", "kt", "java"],
    ]

    static func kind(for item: CleanItem, isDir: Bool) -> String {
        if case .worktree(let repo) = item.action { return (repo as NSString).lastPathComponent }
        if isDir { return "Folder" }
        let ext = (item.path as NSString).pathExtension.lowercased()
        for (name, exts) in groups where exts.contains(ext) { return name }
        return ext.isEmpty ? "Lain" : "Lain"
    }

    static func dates(_ path: String) -> (added: Date?, used: Date?, isDir: Bool) {
        let url = URL(fileURLWithPath: path)
        var added: Date?
        var used: Date?
        if let md = MDItemCreateWithURL(nil, url as CFURL) {
            added = MDItemCopyAttribute(md, kMDItemDateAdded) as? Date
            used = MDItemCopyAttribute(md, kMDItemLastUsedDate) as? Date
        }
        let rv = try? url.resourceValues(forKeys: [.creationDateKey, .contentAccessDateKey, .contentModificationDateKey, .isDirectoryKey])
        added = added ?? rv?.creationDate
        used = used ?? rv?.contentAccessDate ?? rv?.contentModificationDate
        return (added, used, rv?.isDirectory ?? false)
    }

    /// Isi `kind`, `added` dan `lastUsed` secara selari.
    static func enrich(_ items: [CleanItem]) -> [CleanItem] {
        guard !items.isEmpty else { return items }
        var out = items
        let lock = NSLock()
        var results = [Int: (Date?, Date?, String)]()
        DispatchQueue.concurrentPerform(iterations: items.count) { i in
            let d = dates(items[i].path)
            let k = kind(for: items[i], isDir: d.isDir)
            lock.lock()
            results[i] = (d.added, d.used, k)
            lock.unlock()
        }
        for (i, r) in results {
            out[i].added = r.0
            out[i].lastUsed = r.1
            out[i].kind = r.2
        }
        return out
    }
}

// MARK: tapisan dan isihan

enum ItemSort: String, CaseIterable {
    case size = "Saiz"
    case added = "Tarikh ditambah"
    case used = "Terakhir digunakan"
    case name = "Nama"
}

struct ItemFilter {
    var query = ""
    var kind: String?
    var safety: Safety?
    /// Hanya item yang tak digunakan sekurang-kurangnya sekian hari. 0 = semua.
    var idleDays = 0
    var sort: ItemSort = .size

    var active: Bool { !query.isEmpty || kind != nil || safety != nil || idleDays > 0 }

    func apply(_ items: [CleanItem], now: Date = Date()) -> [CleanItem] {
        var list = items
        if !query.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.detail.localizedCaseInsensitiveContains(query) }
        }
        if let kind { list = list.filter { $0.kind == kind } }
        if let safety { list = list.filter { $0.safety == safety } }
        if idleDays > 0 {
            let cutoff = now.addingTimeInterval(-Double(idleDays) * 86400)
            list = list.filter { ($0.lastUsed ?? $0.added).map { $0 < cutoff } ?? false }
        }
        switch sort {
        case .size: list.sort { $0.size > $1.size }
        case .added: list.sort { ($0.added ?? .distantPast) > ($1.added ?? .distantPast) }
        case .used: list.sort { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) }
        case .name: list.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        return list
    }
}
