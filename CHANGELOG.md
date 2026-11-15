# Sejarah versi HSapu

Setiap kemas kini: naikkan `appVersion` dalam `Sources/HSapu/Version.swift`, tambah entri di sini, commit, kemudian `git tag vX.Y.Z`.

## 1.4.1 (2026-11-15)
- **BM campur istilah English:** teks Melayu kini guna istilah biasa dalam English (Settings, History, Update, Download, Scan, Clean, Cleaner, Trash, Monitoring), macam orang sebenarnya bercakap tentang software.

## 1.4.0 (2026-11-15)
- **Sapu menjadi HSapu:** nama baharu, repo awam baharu (`terascoremy/HSapu`) dan laman rasmi di terascore.my/hsapu. Data lama dalam `~/Library/Application Support/Sapu` dipindahkan secara automatik.
- **Dipasang dan dikemas kini seperti HStat:** DMG ditandatangani dengan Developer ID dan dinotarize Apple, dimuat turun dari terascore.my/hsapu. GitHub hanya menyimpan pakej kemas kini kecil (`HSapu-update-<versi>.zip` dan `.sha256`).
- **Kemas kini dalam app:** Tetapan, Kemas kini kini menyemak keluaran awam di GitHub tanpa `gh`, mengesahkan checksum, menggantikan app dan membuka semula. Tiada lagi dmg dimuat turun ke Downloads.
- **Tentang:** kad Tentang dalam Tetapan dengan pembangun (Teras Core Technology Sdn. Bhd.), laman web, emel dan pautan keluaran.
- **Dua bahasa:** Bahasa Melayu dan English, dipilih di Tetapan, Bahasa. Disimpan dan terpakai serta-merta.
- **Warna utama pink:** ikon app dan tema ringkasan, tetapan dan sejarah kini pink. Warna kategori lain kekal.
- Binaan universal (Apple silicon dan Intel).

## 1.3.1 (2026-11-14)
- **Runner GitHub Actions dibuang daripada app:** panel runner dalam halaman Dev, kiraan runner dalam sidebar dan baris runner dalam menu bar dibuang, bersama kod mulakan dan hentikan runner. Dev kini Docker, simulator, emulator dan ruang disk. Runner sebenar di Mac tak disentuh. Folder `actions-runner*` masih muncul dalam kategori Folder home untuk dibersihkan.

## 1.3.0 (2026-11-14)
- **Tapis dan isih dalam setiap kategori:** carian nama, tapisan jenis fail (Folder, Dokumen, Video, Arkib, Gambar, Pemasang, Audio, Kod dan data, Lain; untuk worktree ikut repo), tapisan tahap keselamatan, dan tapisan umur ("tak digunakan lebih 30, 90, 180 hari atau 1 tahun"). Isih ikut saiz, tarikh ditambah, terakhir digunakan atau nama.
- **Butiran tarikh pada setiap baris:** "Ditambah" (Spotlight Date Added, jika tiada tarikh dicipta) dan "Digunakan" (Spotlight Last Used, jika tiada tarikh akses atau ubah).
- **Pilih semua mengikut tapisan:** "Pilih semua (N)" dan "Pilih yang selamat" hanya memilih item yang kelihatan selepas tapisan, kemudian Bersihkan seperti biasa dengan pratonton. Jika ada item terpilih yang tersembunyi oleh tapisan, jumlahnya dipaparkan dengan amaran.
- Cache imbasan lama masih boleh dibaca (medan baru pilihan).

## 1.2.2 (2026-11-14)
- **Kebenaran folder kekal:** `build.sh` kini menandatangani dengan sijil Apple Development dalam Keychain (jika ada) dan bukan ad-hoc. Identiti app sama pada setiap versi, jadi macOS tak lagi minta kebenaran Desktop, Documents, Downloads dan Akses Cakera Penuh selepas setiap kemas kini. Kebenaran diminta sekali lagi pada pemasangan pertama versi ini sahaja.

## 1.2.1 (2026-11-14)
- **Bar kemajuan imbasan:** semasa mengimbas, ringkasan menunjuk bar kemajuan (kategori siap daripada jumlah, peratus, saat berlalu, dan kategori yang masih berjalan). Halaman lain menunjuk pil kecil di penjuru. Sebelum ini butang hanya malap tanpa sebarang tanda kerja.
- **Imbasan jauh lebih pantas:** saiz folder besar (data simulator, folder home, cache dev, node_modules) dicache 3 jam untuk imbasan di latar dan 15 minit untuk imbasan manual, dan dibatalkan bila item itu dipadam. Diukur: imbasan sejuk ~175 saat (xcode 43, home 110), imbasan seterusnya ~16 saat.

## 1.2.0 (2026-11-14)
- **Halaman Sejarah:** setiap tindakan direkod dengan butiran. Kumpulan mengikut hari (jumlah GB dan bilangan item), klik hari untuk lihat setiap tindakan dan item yang dipadam (nama, kategori, cara, saiz). Carta GB sehari, julat 7/30/90 hari atau semua, dan pemilih tarikh untuk lihat berapa GB dipadam pada hari tertentu. Merangkumi pembersih, buang worktree dan tindakan simulator. Rekod lama kekal boleh dibaca (tanpa senarai item).
- **Pembetulan UI:** bahagian atas dan bawah tetingkap terpotong (butang Imbas dan meter cakera hilang) sebab kandungan lebih tinggi daripada tetingkap. Sidebar kini boleh skrol dengan Sejarah, Tetapan dan meter cakera tetap di bawah, jarak baris diketatkan, tetingkap minimum 1100x780 dan lalai 1240x840.

## 1.1.0 (2026-11-14)
Pantas, lebih selamat, dan boleh dipantau.
- **Imbasan pantas:** hasil imbasan terakhir dipaparkan serta-merta bila app dibuka, imbasan baru berjalan senyap di latar. Saiz worktree dicache (`~/Library/Application Support/HSapu`), jadi imbasan kedua tak lagi mengira `du` untuk 200+ folder.
- **Pengurus simulator:** halaman baru. Senarai runtime dan peranti dengan saiz, erase atau padam satu peranti, erase semua yang dimatikan, padam peranti tak tersedia, padam runtime, matikan semua. Peranti yang hidup dilindungi.
- **Pratonton sebelum padam:** lembaran menyenaraikan setiap item, saiz, tahap keselamatan dan apa yang akan berlaku. Pilihan "Alih ke Tong Sampah" supaya boleh dipulihkan.
- **Jangan sentuh:** klik kanan item atau worktree untuk kecualikan selamanya. Diurus dalam Tetapan.
- **Sejarah pembersihan:** jumlah dibebaskan sepanjang masa dan senarai setiap pembersihan.
- **Pemantauan:** notifikasi bila ruang cakera rendah, imbasan automatik harian atau mingguan, buka semasa log masuk. Berjalan selagi Sapu dibuka (ikon bar menu).
- **Akses Cakera Penuh:** Tetapan memeriksa dan membuka tetapan sistem.
- **Kemas kini:** semak keluaran baru di GitHub melalui `gh`, muat turun dmg dari dalam app.
- **Pembinaan:** nombor versi dalam `Version.swift`, dmg bernama `Sapu-<versi>.dmg`, `scripts/notarize.sh` untuk Developer ID dan notarize.
- **Pembetulan:** dialog pengesahan butang Buang worktree membaca pilihan pada masa klik (boleh jadi kosong pada sesetengah versi macOS).
- **Ujian:** `--selftest-core` (42 semakan termasuk kitar hayat simulator ujian yang dicipta dan dipadam sendiri).

## Tanpa versi: 2026-11-14
- GitHub Actions dimatikan dan workflow dibuang. Semua ujian dijalankan di Mac sendiri (`--selftest`, `--selftest-core`), jadi tiada minit Actions digunakan.

## 1.0.0 (2026-11-14)
Keluaran pertama.
- Pembersih gaya CleanMyMac: Sistem, Xcode, Dev, node_modules, Worktree git, Folder home, Downloads, Fail besar.
- Tahap keselamatan selamat/semak/dikunci; tindakan buang, tong sampah, `git worktree remove`, padam simulator.
- Nyah-pendua: kiraan tak lagi berganda antara kategori; folder yang ada worktree dikunci.
- Hab kerja: pengurus worktree dan sesi Claude, penjejak build dan release (Expo/Flutter/native + status CI), papan pemuka dev (runner GitHub Actions, Docker, simulator, ruang cakera).
- Ikon menu bar.
- Ujian terbina: `--selftest`, `--selftest-hub`, `--scan`, `--shot`.
- Pembungkusan: `scripts/build.sh` menghasilkan `dist/Sapu.app` dan dmg (tanda tangan ad-hoc, belum notarize).
