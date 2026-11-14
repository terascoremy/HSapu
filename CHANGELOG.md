# Sejarah versi Sapu

Setiap kemas kini: naikkan `VERSION` dalam `scripts/build.sh`, tambah entri di sini, commit, kemudian `git tag vX.Y.Z`.

## 1.0.0 — 2026-11-14
Keluaran pertama.
- Pembersih gaya CleanMyMac: Sistem, Xcode, Dev, node_modules, Worktree git, Folder home, Downloads, Fail besar.
- Tahap keselamatan selamat/semak/dikunci; tindakan buang, tong sampah, `git worktree remove`, padam simulator.
- Nyah-pendua: kiraan tak lagi berganda antara kategori; folder yang ada worktree dikunci.
- Hab kerja: pengurus worktree dan sesi Claude, penjejak build dan release (Expo/Flutter/native + status CI), papan pemuka dev (runner GitHub Actions, Docker, simulator, ruang cakera).
- Ikon menu bar.
- Ujian terbina: `--selftest`, `--selftest-hub`, `--scan`, `--shot`.
- Pembungkusan: `scripts/build.sh` menghasilkan `dist/Sapu.app` dan dmg (tanda tangan ad-hoc, belum notarize).
