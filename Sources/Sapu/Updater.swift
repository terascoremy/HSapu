import AppKit
import Foundation

struct UpdateInfo {
    let version: String
    let tag: String
    let url: String
    let notes: String
    let dmgName: String?
}

enum UpdateResult {
    case available(UpdateInfo)
    case upToDate
    case failed(String)
}

/// Semak keluaran baru pada repo GitHub melalui `gh` (repo peribadi memerlukan log masuk gh).
enum Updater {
    static let gh = "/opt/homebrew/bin/gh"

    static func parts(_ v: String) -> [Int] {
        v.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            .split(separator: "-").first.map { $0.split(separator: ".").map { Int($0) ?? 0 } } ?? []
    }

    static func newer(_ a: String, than b: String) -> Bool {
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    static func parse(_ json: String, current: String) -> UpdateResult {
        guard let data = json.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = o["tagName"] as? String else { return .failed("Jawapan GitHub tak dapat dibaca") }
        guard newer(tag, than: current) else { return .upToDate }
        let assets = (o["assets"] as? [[String: Any]]) ?? []
        let dmg = assets.compactMap { $0["name"] as? String }.first { $0.hasSuffix(".dmg") }
        return .available(UpdateInfo(version: tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV")), tag: tag,
                                     url: o["url"] as? String ?? "https://github.com/\(appRepo)/releases",
                                     notes: o["body"] as? String ?? "", dmgName: dmg))
    }

    static func check(current: String = appVersion) -> UpdateResult {
        guard FileManager.default.isExecutableFile(atPath: gh) else {
            return .failed("GitHub CLI (gh) tak dipasang, jadi kemas kini tak dapat disemak")
        }
        let r = Shell.run(gh, ["release", "view", "--repo", appRepo, "--json", "tagName,url,body,assets"], mergeErr: true, timeout: 25)
        if r.status != 0 {
            if r.out.contains("release not found") { return .upToDate }
            let msg = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failed(msg.isEmpty ? "Tak dapat hubungi GitHub" : String(msg.prefix(160)))
        }
        return parse(r.out, current: current)
    }

    /// Muat turun dmg ke Downloads dan buka. Mengembalikan mesej ralat jika gagal.
    static func download(_ info: UpdateInfo) -> String? {
        guard let name = info.dmgName else { return "Keluaran ini tiada fail dmg" }
        let dir = NSHomeDirectory() + "/Downloads"
        let r = Shell.run(gh, ["release", "download", info.tag, "--repo", appRepo, "--pattern", name, "--dir", dir, "--clobber"],
                          mergeErr: true, timeout: 300)
        guard r.status == 0 else { return String(r.out.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160)) }
        let path = dir + "/" + name
        DispatchQueue.main.async { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
        return nil
    }
}
