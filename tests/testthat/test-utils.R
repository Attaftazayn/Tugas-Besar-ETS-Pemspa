# =============================================================================
# Pengujian fungsi bantu murni (utils.R)
# -----------------------------------------------------------------------------
# Utilitas ini dipakai saat pencocokan nama kecamatan antara CSV statistik dan
# poligon batas; kesalahan kecil di sini akan membuat statistik tidak ter-join.
# =============================================================================

# Cari akar proyek (tempat utils.R berada) tanpa bergantung pada working dir
cari_akar <- function() {
  p <- getwd()
  for (i in seq_len(8)) {
    if (file.exists(file.path(p, "utils.R"))) return(p)
    induk <- dirname(p)
    if (identical(induk, p)) break
    p <- induk
  }
  stop("utils.R tidak ditemukan dari ", getwd())
}
source(file.path(cari_akar(), "utils.R"))


test_that("normalisasi_nama menyeragamkan huruf besar/kecil dan spasi tepi", {
  expect_equal(normalisasi_nama("Kebon Sari"), "kebon sari")
  expect_equal(normalisasi_nama("  Kebon Sari "), "kebon sari")
  expect_equal(normalisasi_nama("MADIUN"), "madiun")
  expect_equal(normalisasi_nama("\tTaman\n"), "taman")
})

test_that("normalisasi_nama tidak merusak nama yang sudah benar", {
  expect_equal(normalisasi_nama(c("Dagangan", "Dolopo")),
               c("dagangan", "dolopo"))
  expect_equal(normalisasi_nama(character(0)), character(0))
})

test_that("normalisasi_nama membuat nama identik menjadi cocok", {
  # dasar pencocokan antara CSV dan poligon
  expect_equal(normalisasi_nama("  Balerejo "), normalisasi_nama("balerejo"))
})


test_that("cari_file mengembalikan NA bila berkas tidak ada", {
  folder <- file.path(tempdir(), "uji-kosong")
  dir.create(folder, showWarnings = FALSE, recursive = TRUE)
  on.exit(unlink(folder, recursive = TRUE), add = TRUE)
  expect_true(is.na(cari_file(folder, "^tidak-ada-xyz$")))
})

test_that("cari_file menemukan berkas tanpa peduli kapital dan mengembalikan pola pertama", {
  folder <- file.path(tempdir(), "uji-isi")
  dir.create(folder, showWarnings = FALSE, recursive = TRUE)
  on.exit(unlink(folder, recursive = TRUE), add = TRUE)

  writeLines("a", file.path(folder, "NDVI_madiun.tif"))
  writeLines("b", file.path(folder, "Zonal_Statistics_Madiun.csv"))

  p_tif <- cari_file(folder, "^ndvi_madiun\\.tif$")   # huruf kecil tetap ketemu
  expect_true(file.exists(p_tif))

  p_csv <- cari_file(folder, "^Zonal_Statistics_Madiun\\.csv$")
  expect_true(file.exists(p_csv))
})

test_that("cari_file mengabaikan folder yang namanya mirip", {
  folder <- file.path(tempdir(), "uji-folder")
  dir.create(folder, showWarnings = FALSE, recursive = TRUE)
  on.exit(unlink(folder, recursive = TRUE), add = TRUE)

  dir.create(file.path(folder, "batas_kota"))   # folder, bukan berkas
  writeLines("x", file.path(folder, "batas_kecamatan.shp"))

  p <- cari_file(folder, "^batas")
  expect_equal(basename(p), "batas_kecamatan.shp")
})
