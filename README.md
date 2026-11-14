# Sapu

Pembersih Mac dan hab kerja untuk developer. Native SwiftUI, macOS 14+.

- **Pembersih:** cache sistem, Xcode, cache developer, `node_modules`, worktree git, folder home, Downloads, fail besar. Setiap item ada tahap keselamatan, pratonton sebelum padam, dan pilihan hantar ke Tong Sampah.
- **Kerja:** pengurus worktree, penjejak build dan release (versi, nombor build, status CI), papan pemuka dev (runner GitHub Actions, Docker, simulator, disk).
- **Simulator:** runtime dan peranti dengan saiz, erase atau padam.
- **Latar:** ikon bar menu, notifikasi ruang cakera rendah, imbasan berjadual.

## Bina

```bash
swift build                 # debug
./scripts/build.sh          # dist/Sapu.app dan dist/Sapu-<versi>.dmg
```

Versi ditetapkan dalam `Sources/Sapu/Version.swift` sahaja.

## Ujian

```bash
.build/debug/Sapu --selftest        # pembersihan dan worktree
.build/debug/Sapu --selftest-core   # cache, kecualian, sejarah, simulator, kemas kini
.build/debug/Sapu --selftest-hub    # hab (menyentuh runner dan Terminal sebenar, jalankan tangan)
.build/debug/Sapu --scan [--big] [--all]   # imbas tanpa GUI
.build/debug/Sapu --shot <folder>   # tangkap skrin setiap halaman
.build/debug/Sapu --check-update [versi]   # semak keluaran baru di GitHub
```

## Keluaran

1. Naikkan `appVersion` dalam `Version.swift`.
2. Tambah entri di `CHANGELOG.md`.
3. `./scripts/build.sh`, commit, `git tag vX.Y.Z`, `git push --tags`.
4. `gh release create vX.Y.Z dist/Sapu-X.Y.Z.dmg --notes-file ...` supaya semakan kemas kini dalam app nampak versi baru.

Tanpa akaun Apple Developer, app hanya bertanda tangan ad-hoc (pemasangan pertama: klik kanan, Open).
Dengan akaun, `SIGN_ID="Developer ID Application: ..." ./scripts/notarize.sh` menandatangani, notarize dan staple dmg.
