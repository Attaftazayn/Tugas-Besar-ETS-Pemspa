# Changelog

Seluruh perubahan penting pada proyek ini dicatat di berkas ini.
Format mengikuti [Keep a Changelog](https://keepachangelog.com/id/1.1.0/),
dan nomor versi mengikuti [Semantic Versioning](https://semver.org/id/spec/v2.0.0.html).

## [Unreleased]

### Added
- Fungsi bantu dipisahkan ke `utils.R` agar dapat diuji.
- Pengujian unit `testthat` untuk `normalisasi_nama()` dan `cari_file()`.
- Kolom **Luas (ha)** pada tooltip/popup dan tabel statistik zonal.
- Modal **Tentang** berisi metadata citra, rumus indeks, dan penulis.
- Klasifikasi indeks (kelas) dengan legenda kategori.
- Tombol **bookmark** untuk membagikan tautan dengan pilihan filter.
- Spinner CSS saat raster dimuat serta dukungan layar kecil (responsif).
- Perpindahan ke kecamatan pilihan pada peta saat diklik dari grafik/tabel.
- `CHANGELOG.md` dan templat laporan isu GitHub.
- Script deployment ke shinyapps.io.

### Changed
- NDCI dihitung dengan rumus (Red − NIR) / (Red + NIR).
- Tabel statistik menampilkan seluruh kecamatan dalam satu halaman.
- Klik batang grafik kini menyorot kecamatan dan memilih baris tabelnya.
- README: rumus NDCI didokumentasikan dengan tepat.

### Fixed
- Klik batang grafik tidak menyorot kecamatan (registrasi event plotly).
- Kolom NDCI pada `Zonal_Statistics_Madiun.csv` identik dengan NDVI.

## [1.0.0] - 2026-10-16

### Added
- Versi pertama yang dirilis.
- Aplikasi WebGIS Shiny + shinydashboard + leaflet.
- Empat indeks spektral Sentinel-2: NDVI, NDBI, NDWI, NDCI.
- Statistik zonal per kecamatan (18 kecamatan Kab. & Kota Madiun).
- Skrip praproses `tubes.R` dan tabel `Zonal_Statistics_Madiun.csv`.
- README profesional, tangkapan layar, lisensi MIT, dan `CITATION.cff`.

[Unreleased]: https://github.com/Attaftazayn/Tugas-Besar-ETS-Pemspa/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/Attaftazayn/Tugas-Besar-ETS-Pemspa/releases/tag/v1.0.0
