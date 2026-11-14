import Foundation
import SwiftUI

enum Safety: Int {
    case safe, review, locked
}

enum CleanAction {
    case delete
    case deleteContents
    case trash
    case trashList([String])
    case worktree(repo: String)
    case simulatorErase
}

struct CleanItem: Identifiable {
    let id = UUID()
    var name: String
    var path: String
    var detail: String
    var size: Int64
    var safety: Safety
    var action: CleanAction
    var selected: Bool
}

struct Theme: Equatable {
    let id: String
    let a: Color
    let b: Color
    let glow: Color

    static func == (l: Theme, r: Theme) -> Bool { l.id == r.id }

    static let overview = Theme(id: "overview", a: Color(hex: 0x2E1A6B), b: Color(hex: 0x0D0A2B), glow: Color(hex: 0x7A4DFF))
}

struct CleanCategory: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let theme: Theme
    var items: [CleanItem] = []
    var scanned = false

    var total: Int64 { items.filter { $0.safety != .locked }.reduce(0) { $0 + $1.size } }
    var selectedItems: [CleanItem] { items.filter { $0.selected && $0.safety != .locked } }
    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }
}

enum Selection: Hashable {
    case overview
    case worktrees
    case builds
    case dev
    case category(String)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

func fmt(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

enum Catalog {
    static func blank() -> [CleanCategory] {
        [
            CleanCategory(id: "system", title: "Sampah sistem", subtitle: "Cache aplikasi, log dan Tong Sampah.", icon: "trash.fill",
                          theme: Theme(id: "system", a: Color(hex: 0x0F5A36), b: Color(hex: 0x051D11), glow: Color(hex: 0x2ECC71))),
            CleanCategory(id: "xcode", title: "Xcode", subtitle: "Fail build, simbol peranti dan data simulator.", icon: "hammer.fill",
                          theme: Theme(id: "xcode", a: Color(hex: 0x0C3F85), b: Color(hex: 0x05122B), glow: Color(hex: 0x3B9BFF))),
            CleanCategory(id: "dev", title: "Cache developer", subtitle: "Gradle, npm, model AI dan emulator Android.", icon: "shippingbox.fill",
                          theme: Theme(id: "dev", a: Color(hex: 0x7F3D0C), b: Color(hex: 0x261004), glow: Color(hex: 0xFF9A3B))),
            CleanCategory(id: "node", title: "node_modules", subtitle: "Boleh dipasang semula dengan npm install.", icon: "cube.fill",
                          theme: Theme(id: "node", a: Color(hex: 0x0B5F64), b: Color(hex: 0x041D20), glow: Color(hex: 0x2ED3C6))),
            CleanCategory(id: "worktree", title: "Worktree git", subtitle: "Salinan projek daripada sesi Claude Code dan git worktree lain.", icon: "arrow.triangle.branch",
                          theme: Theme(id: "worktree", a: Color(hex: 0x5C1466), b: Color(hex: 0x1C0622), glow: Color(hex: 0xE056FD))),
            CleanCategory(id: "home", title: "Folder home", subtitle: "Folder besar dalam folder pengguna, sandaran lama dan data alat.", icon: "house.fill",
                          theme: Theme(id: "home", a: Color(hex: 0x33415C), b: Color(hex: 0x0D1424), glow: Color(hex: 0x8FA3C7))),
            CleanCategory(id: "downloads", title: "Downloads", subtitle: "Pemasang, pendua dan fail lama dalam folder Downloads.", icon: "arrow.down.circle.fill",
                          theme: Theme(id: "downloads", a: Color(hex: 0x6E5607), b: Color(hex: 0x211A03), glow: Color(hex: 0xEAB308))),
            CleanCategory(id: "big", title: "Fail besar", subtitle: "Fail melebihi 300 MB dalam Desktop, Documents dan Movies.", icon: "doc.fill",
                          theme: Theme(id: "big", a: Color(hex: 0x7D143B), b: Color(hex: 0x270612), glow: Color(hex: 0xFF5C8A))),
        ]
    }
}
