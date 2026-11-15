import AppKit
import CryptoKit
import Foundation

struct UpdateInfo {
    let version: String
    let tag: String
    let url: String
    let notes: String
    let package: String?        // name of the update .zip
    let packageURL: String?
    let checksumURL: String?
}

enum UpdateResult {
    case available(UpdateInfo)
    case upToDate
    case failed(String)
}

/// Updates come from GitHub releases on terascoremy/HSapu. A release carries only the small
/// update package (HSapu-update-<ver>.zip + .sha256). The disk image is downloaded from terascore.my/hsapu.
enum Updater {
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

    /// Parses the GitHub "latest release" JSON.
    static func parse(_ json: String, current: String) -> UpdateResult {
        guard let data = json.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = o["tag_name"] as? String else { return .failed("Could not read the GitHub reply") }
        guard newer(tag, than: current) else { return .upToDate }
        let assets = (o["assets"] as? [[String: Any]]) ?? []
        func asset(_ test: (String) -> Bool) -> (String, String)? {
            for a in assets { if let n = a["name"] as? String, test(n.lowercased()), let u = a["browser_download_url"] as? String { return (n, u) } }
            return nil
        }
        let pkg = asset { $0.hasSuffix(".zip") }
        let sum = asset { $0.hasSuffix(".sha256") }
        return .available(UpdateInfo(version: tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV")), tag: tag,
                                     url: o["html_url"] as? String ?? "https://github.com/\(appRepo)/releases",
                                     notes: o["body"] as? String ?? "", package: pkg?.0, packageURL: pkg?.1, checksumURL: sum?.1))
    }

    private static func fetch(_ url: URL, timeout: TimeInterval) -> (Data?, Int, String?) {
        var req = URLRequest(url: url); req.timeoutInterval = timeout
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("HSapu-Updater", forHTTPHeaderField: "User-Agent")
        let sem = DispatchSemaphore(value: 0)
        var out: (Data?, Int, String?) = (nil, 0, nil)
        URLSession.shared.dataTask(with: req) { d, r, e in
            out = (d, (r as? HTTPURLResponse)?.statusCode ?? 0, e?.localizedDescription); sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + timeout + 5)
        return out
    }

    static func check(current: String = appVersion) -> UpdateResult {
        let (data, code, err) = fetch(URL(string: "https://api.github.com/repos/\(appRepo)/releases/latest")!, timeout: 15)
        if code == 404 { return .upToDate }
        guard code == 200, let data else { return .failed(err ?? "GitHub returned HTTP \(code)") }
        return parse(String(decoding: data, as: UTF8.self), current: current)
    }

    /// Downloads the update zip, verifies its checksum, replaces the running app and relaunches.
    /// Returns an error message on failure; on success the app quits and the new version opens.
    static func install(_ info: UpdateInfo) -> String? {
        guard let s = info.packageURL, let url = URL(string: s) else { return "This release has no update package" }
        guard url.host?.hasSuffix("github.com") == true || url.host?.hasSuffix("githubusercontent.com") == true else { return "Unexpected download host" }
        let (data, code, err) = fetch(url, timeout: 300)
        guard code == 200, let data else { return err ?? "Download failed (HTTP \(code))" }
        if let cs = info.checksumURL, let cu = URL(string: cs) {
            let (d, c, _) = fetch(cu, timeout: 30)
            guard c == 200, let d else { return "Checksum could not be fetched" }
            let expected = String(decoding: d, as: UTF8.self).split(whereSeparator: { $0 == " " || $0 == "\n" }).first.map(String.init)?.lowercased() ?? ""
            let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard expected == actual else { return "Checksum mismatch. Update rejected." }
        }
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("hsapu-update-\(UUID().uuidString)")
        let zip = work.appendingPathComponent("update.zip")
        do { try fm.createDirectory(at: work, withIntermediateDirectories: true); try data.write(to: zip) } catch { return error.localizedDescription }
        let unzip = Process(); unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto"); unzip.arguments = ["-xk", zip.path, work.path]
        do { try unzip.run() } catch { return error.localizedDescription }
        unzip.waitUntilExit()
        guard unzip.terminationStatus == 0 else { return "Could not unpack the update" }
        let found = fm.enumerator(at: work, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL }.first { $0.lastPathComponent == "HSapu.app" }
        guard let newApp = found, let plist = NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist")),
              plist["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier else { return "The package does not contain a valid HSapu.app" }
        let target = Bundle.main.bundleURL
        guard fm.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
            DispatchQueue.main.async { NSWorkspace.shared.activateFileViewerSelecting([newApp]) }
            return "No permission to replace the app here. The new version was opened in Finder, drag it to Applications."
        }
        let script = "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.3; done; rm -rf \"\(target.path)\" && /usr/bin/ditto \"\(newApp.path)\" \"\(target.path)\" && /usr/bin/open \"\(target.path)\"; rm -rf \"\(work.path)\""
        let sh = Process(); sh.executableURL = URL(fileURLWithPath: "/bin/sh"); sh.arguments = ["-c", script]
        do { try sh.run() } catch { return error.localizedDescription }
        DispatchQueue.main.async { NSApp.terminate(nil) }
        return nil
    }
}
