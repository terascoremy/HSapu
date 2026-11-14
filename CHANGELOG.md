# Sejarah versi Sapu

Setiap kemas kini: naikkan `VERSION` dalam `scripts/build.sh`, tambah entri di sini, commit, kemudian `git tag vX.Y.Z`.

## 1.1.0 — 2026-11-14
Pantas, lebih selamat, dan boleh dipantau.
- **Imbasan pantas:** hasil imbasan terakhir dipaparkan serta-merta bila app dibuka, imbasan baru berjalan senyap di latar. Saiz worktree dicache (`~/Library/Application Support/Sapu`), jadi imbasan kedua tak lagi mengira `du` untuk 200+ folder.
- **Pengurus simulator:** halaman baru. Senarai runtime dan peranti dengan saiz, erase atau padam satu peranti, erase semua yang dimatikan, padam peranti tak tersedia, padam runtime, matikan semua. Peranti yang hidup dilindungi.
- **Pratonton sebelum padam:** lembaran menyenaraikan setiap item, saiz, tahap keselamatan dan apa yang akan berlaku. Pilihan "Alih ke Tong Sampah" supaya boleh dipulihkan.
- **Jangan sentuh:** klik kanan item atau worktree untuk kecualikan selamanya. Diurus dalam Tetapan.
- **Sejarah pembersihan:** jumlah dibebaskan sepanjang masa dan senarai setiap pembersihan.
- **Pemantauan:** notifikasi bila ruang cakera rendah, imbasan automatik harian atau mingguan, buka semasa log masuk. Berjalan selagi Sapu dibuka (ikon bar menu).
- **Akses Cakera Penuh:** Tetapan memeriksa dan membuka tetapan sistem.
- **Kemas kini:** semak keluaran baru di GitHub melalui `gh`, muat turun dmg dari dalam app.
- **Pembinaan:** nombor versi dalam `Version.swift`, dmg bernama `Sapu-<versi>.dmg`, `scripts/notarize.sh` untuk Developer ID dan notarize, CI GitHub Actions (build + ujian) pada tag.
- **Pembetulan:** dialog pengesahan butang Buang worktree membaca pilihan pada masa klik (boleh jadi kosong pada sesetengah versi macOS).
- **Ujian:** `--selftest-core` (42 semakan termasuk kitar hayat simulator ujian yang dicipta dan dipadam sendiri).

## 1.0.0 — 2026-11-14
Keluaran pertama.
- Pembersih gaya CleanMyMac: Sistem, Xcode, Dev, node_modules, Worktree git, Folder home, Downloads, Fail besar.
- Tahap keselamatan selamat/semak/dikunci; tindakan buang, tong sampah, `git worktree remove`, padam simulator.
- Nyah-pendua: kiraan tak lagi berganda antara kategori; folder yang ada worktree dikunci.
- Hab kerja: pengurus worktree dan sesi Claude, penjejak build dan release (Expo/Flutter/native + status CI), papan pemuka dev (runner GitHub Actions, Docker, simulator, ruang cakera).
- Ikon menu bar.
- Ujian terbina: `--selftest`, `--selftest-hub`, `--scan`, `--shot`.
- Pembungkusan: `scripts/build.sh` menghasilkan `dist/Sapu.app` dan dmg (tanda tangan ad-hoc, belum notarize).
