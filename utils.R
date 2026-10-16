# =============================================================================
# Fungsi bantu murni (tanpa efek samping) untuk app.R
# -----------------------------------------------------------------------------
# Dipisahkan ke berkas tersendiri agar dapat diuji tanpa menjalankan aplikasi.
# Lihat tests/testthat/test-utils.R. Berkas ini di-`source()` oleh app.R.
# =============================================================================

# Mencari satu berkas di dalam folder berdasarkan pola nama (regex).
# Mengembalikan path lengkap berkas pertama yang cocok, atau NA bila tidak ada.
# ignore.case = TRUE membuat pencarian tidak terpengaruh huruf besar/kecil.
cari_file <- function(folder, pola) {
  hasil <- list.files(folder, pattern = pola, full.names = TRUE,
                      ignore.case = TRUE)
  hasil <- hasil[!dir.exists(hasil)]          # abaikan nama folder
  if (length(hasil) == 0) return(NA_character_)
  hasil[1]
}

# Menyeragamkan nama kecamatan untuk pencocokan: huruf kecil & tanpa spasi tepi.
normalisasi_nama <- function(x) tolower(trimws(x))
