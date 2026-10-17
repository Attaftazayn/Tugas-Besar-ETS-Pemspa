# =============================================================================
# Deploy aplikasi ke shinyapps.io
# -----------------------------------------------------------------------------
# PRASARATA (sekali saja, jalankan di konsol R Anda sendiri):
#
#   install.packages("rsconnect")
#
#   Lalu buka https://www.shinyapps.io -> Account -> Tokens -> Add Token,
#   salin "Token" dan "Secret", lalu isi di bawah (jangan commit berkas ini
#   bila sudah berisi kredensial; berkas ini sengaja TIDAK menyimpan token):
#
#   rsconnect::setAccountInfo(
#     name   = "<nama akun shinyapps.io Anda>",
#     token  = "<token>",
#     secret = "<secret>"
#   )
#
# CARA PAKAI:
#   Rscript scripts/deploy_shinyapps.R
# =============================================================================

library(rsconnect)

folder_data   <- "Data"
folder_output <- "output"

# Fungsi bantu pencarian berkas (senada dengan utils.R)
cari_berkas <- function(folder, pola) {
  h <- list.files(folder, pattern = pola, full.names = TRUE, ignore.case = TRUE)
  h <- h[!dir.exists(h)]
  if (length(h) == 0) return(NA_character_)
  h[1]
}

# Berkas yang benar-benar dibutuhkan saat aplikasi berjalan.
# Sengaja tidak menyertakan: output/citra_madiun.tif (36 MB, tidak dipakai
# aplikasi), tubes.R (praproses), docs/, tests/, dan berkas git.
file_batas  <- cari_berkas(folder_data,   "^batas")
file_zonal  <- cari_berkas(folder_output, "^Zonal_Statistics_Madiun\\.csv$")
file_indeks <- c(
  cari_berkas(folder_output, "^NDVI_madiun\\.tif$"),
  cari_berkas(folder_output, "^NDBI_madiun\\.tif$"),
  cari_berkas(folder_output, "^NDWI_madiun\\.tif$"),
  cari_berkas(folder_output, "^NDCI_Cloud_Madiun\\.tif$")
)

file_wajib <- c("app.R", "utils.R", file_batas, file_zonal, file_indeks)

if (any(is.na(file_wajib)) || !all(file.exists(file_wajib))) {
  stop("Berkas wajib tidak lengkap:\n  ",
       paste(file_wajib[is.na(file_wajib) | !file.exists(file_wajib)],
             collapse = "\n  "))
}

total_mb <- round(sum(file.info(file_wajib)$size) / 1024^2, 1)
cat("Berkas yang akan dibundel (", length(file_wajib), " berkas, ",
    total_mb, " MB ):\n", sep = "")
cat("  ", paste(file_wajib, collapse = "\n   "), "\n\n", sep = "")

# --- Deploy -----------------------------------------------------------------
# appName menjadi alamat aplikasi: https://<akun>.shinyapps.io/<appName>/
deployApp(
  appDir         = ".",
  appFiles       = file_wajib,
  appName        = "webgis-indeks-madiun",
  launch.browser = TRUE
)
