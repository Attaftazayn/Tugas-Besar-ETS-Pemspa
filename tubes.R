# ====================================
# 1. PENGATURAN PROJ
# ====================================

Sys.unsetenv("PROJ_LIB")
Sys.unsetenv("PROJ_DATA")
Sys.unsetenv("GDAL_DATA")

# ====================================
# 2. MEMANGGIL LIBRARY
# ====================================

library(shiny)
library(shinydashboard)
library(leaflet)
library(leaflet.extras)
library(sf)
library(terra)
library(dplyr)
library(DT)

# ====================================
# 3. MENENTUKAN FOLDER
# ====================================

setwd("C:/SEMESTER 5/PEMSPA/TUBES ETS")

folder_citra <- "C:/SEMESTER 5/PEMSPA/TUBES ETS/Data"

# ====================================
# 4. MENCARI FILE CITRA
# ====================================

files <- list.files(
  folder_citra,
  pattern = "\\.jp2$",
  recursive = TRUE,
  full.names = TRUE
)

print(files)

# ====================================
# 5. MEMBACA BAND SENTINEL-2
# ====================================

ambil_band <- function(kode) {
  
  hasil <- grep(
    kode,
    files,
    value = TRUE
  )
  
  if (length(hasil) != 1) {
    stop(paste("Periksa file band:", kode))
  }
  
  rast(hasil)
}

B03 <- ambil_band("B03_10m")
B04 <- ambil_band("B04_10m")
B08 <- ambil_band("B08_10m")
B11 <- ambil_band("B11_20m")

# ====================================
# 6. MENAMPILKAN CITRA
# ====================================

plot(B04, main = "Sentinel-2 Band 4")

# Memeriksa sistem koordinat
crs(B04)

# ====================================
# 7. MEMBACA BATAS ADMINISTRASI
# ====================================

madiun <- st_read(
  "C:/SEMESTER 5/PEMSPA/TUBES ETS/Data/batas madiun"
)

# Menampilkan data atribut
print(madiun)

# Melihat sistem koordinat
st_crs(madiun)

# Menampilkan batas wilayah
plot(st_geometry(madiun))


# ====================================
# 8. MENYAMAKAN RESOLUSI
# ====================================

B03_new <- resample(B03, B11, method = "bilinear")
B04_new <- resample(B04, B11, method = "bilinear")
B08_new <- resample(B08, B11, method = "bilinear")

# Memeriksa kesamaan raster
print(compareGeom(B03_new, B11))
print(compareGeom(B04_new, B11))
print(compareGeom(B08_new, B11))

# ====================================
# 9. MENGGABUNGKAN BAND
# ====================================

citra <- c(
  B03_new,
  B04_new,
  B08_new,
  B11
)

names(citra) <- c(
  "B03", "B04", "B08", "B11"
)

print(citra)

# ====================================
# 10. MENYAMAKAN KOORDINAT BATAS
# ====================================

# Mengubah sf menjadi SpatVector
batas <- vect(madiun)

# Menyamakan CRS dengan citra
batas <- project(
  batas,
  crs(citra)
)

# Menampilkan batas wilayah
plot(batas)

# ====================================
# 11. CROP DAN MASK
# ====================================

# Memotong citra menggunakan batas
citra_crop <- crop(
  citra,
  batas
)

# Menghilangkan area di luar batas
citra_mask <- mask(
  citra_crop,
  batas
)

# Menampilkan hasil crop
plot(
  citra_mask$B04,
  main = "Hasil Crop Kabupaten madiun"
)

# ====================================
# 12. MENYIMPAN HASIL
# ====================================

# Membuat folder output
dir.create(
  "output",
  showWarnings = FALSE
)

# Menyimpan raster hasil crop
writeRaster(
  citra_mask,
  "output/citra_madiun.tif",
  overwrite = TRUE
)

# ====================================
# 13. MEMERIKSA HASIL
# ====================================

print(citra_mask)

plot(citra_mask)

# ====================================
# 14. MENGHITUNG NDVI
# ====================================

NDVI <- (citra_mask$B08 - citra_mask$B04) /
  (citra_mask$B08 + citra_mask$B04)

# Memberikan nama raster
names(NDVI) <- "NDVI"

# Menampilkan hasil
plot(
  NDVI,
  col = hcl.colors(100, "YlGn"),
  main = "Peta NDVI Kabupaten madiun"
)

# Menyimpan hasil
writeRaster(
  NDVI,
  "output/NDVI_madiun.tif",
  overwrite = TRUE
)

# ====================================
# 15. MENGHITUNG NDBI
# ====================================

NDBI <- (citra_mask$B11 - citra_mask$B08) /
  (citra_mask$B11 + citra_mask$B08)

names(NDBI) <- "NDBI"

plot(
  NDBI,
  col = hcl.colors(100, "YlOrRd"),
  main = "Peta NDBI Kabupaten madiun"
)

writeRaster(
  NDBI,
  "output/NDBI_madiun.tif",
  overwrite = TRUE
)

# ====================================
# 16. MENGHITUNG NDWI
# ====================================

NDWI <- (citra_mask$B03 - citra_mask$B08) /
  (citra_mask$B03 + citra_mask$B08)

names(NDWI) <- "NDWI"

plot(
  NDWI,
  col = hcl.colors(100, "Blues 3"),
  main = "Peta NDWI Kabupaten madiun"
)

writeRaster(
  NDWI,
  "output/NDWI_madiun.tif",
  overwrite = TRUE
)

# ====================================
# 17. MENGHITUNG NDCI
# ====================================

# ====================================

# Membaca SCL resolusi 20 meter
SCL <- ambil_band("SCL_20m")

# Menyamakan grid dengan citra
SCL_new <- resample(
  SCL,
  B11,
  method = "near"
)

# Crop dan mask wilayah Lamongan
SCL_crop <- crop(SCL_new, batas)
SCL_mask <- mask(SCL_crop, batas)

# Menampilkan SCL
plot(
  SCL_mask,
  main = "Scene Classification Layer madiun"
)
# Mengidentifikasi awan
AWAN <- ifel(
  SCL_mask %in% c(8, 9, 10),
  1,
  0
)

names(AWAN) <- "AWAN"

# Menampilkan hasil
plot(
  AWAN,
  col = c("white", "gray40"),
  main = "Peta Sebaran Awan Madiun"
)

# Menyimpan hasil
writeRaster(
  AWAN,
  "output/AWAN_Madiun.tif",
  overwrite = TRUE
)
# ====================================
# 18. SIMPAN 4 PETA
# ====================================

png(
  "output/4_Peta_Madiun.png",
  width = 2400,
  height = 1800,
  res = 200
)

par(mfrow = c(2, 2))

plot(NDVI,
     col = hcl.colors(100, "YlGn"),
     main = "NDVI - Vegetasi")

plot(NDBI,
     col = hcl.colors(100, "YlOrRd"),
     main = "NDBI - Terbangun")

plot(NDWI,
     col = hcl.colors(100, "Blues 3"),
     main = "NDWI - Perairan")

plot(AWAN,
     col = c("white", "gray40"),
     breaks = c(-0.5, 0.5, 1.5),
     main = "Sebaran Awan")

dev.off()
par(mfrow = c(1, 1))

# ====================================
# 19. MENAMPILKAN 4 PETA
# ====================================

# Mengatur tampilan 2 baris dan 2 kolom
par(mfrow = c(2, 2))

# Peta NDVI
plot(
  NDVI,
  col = hcl.colors(100, "YlGn"),
  main = "NDVI - Vegetasi"
)

# Peta NDBI
plot(
  NDBI,
  col = hcl.colors(100, "YlOrRd"),
  main = "NDBI - Bangunan"
)

# Peta NDWI
plot(
  NDWI,
  col = hcl.colors(100, "Blues 3"),
  main = "NDWI - Perairan"
)

# Peta AWAN
plot(
  AWAN,
  col = c("white", "gray40"),
  breaks = c(-0.5, 0.5, 1.5),
  main = "Sebaran Awan"
)

# Mengembalikan tampilan normal
par(mfrow = c(1, 1))

# ====================================
# 20. MEMERIKSA DATA KECAMATAN
# ====================================

# Membaca ulang GeoJSON agar mulai dari data asli
kecamatan <- st_read(
  "C:/SEMESTER 5/PEMSPA/TUBES ETS/Data/batas madiun"
)

# Memeriksa jumlah data
print(nrow(kecamatan))

# Memeriksa nama kolom
print(names(kecamatan))

# Memeriksa geometri kosong
print(sum(st_is_empty(kecamatan)))

# Menghapus geometri kosong
kecamatan <- kecamatan[
  !st_is_empty(kecamatan), ,
  drop = FALSE
]

# Memperbaiki geometri tidak valid
kecamatan <- st_make_valid(kecamatan)

# Memeriksa jumlah data setelah dibersihkan
print(nrow(kecamatan))

# Memeriksa validitas geometri
print(table(st_is_valid(kecamatan)))

# Menampilkan batas kecamatan
plot(
  st_geometry(kecamatan),
  main = "Batas Kecamatan Madiun"
)
# ====================================
# 21. MEMBERSIHKAN DATA KECAMATAN
# ====================================

# Menghapus geometri kosong
kecamatan <- kecamatan[
  !st_is_empty(kecamatan),
]

# Memperbaiki geometri tidak valid
kecamatan <- st_make_valid(kecamatan)

# Memeriksa kembali jumlah wilayah
nrow(kecamatan)

# Menampilkan hasil
plot(
  st_geometry(kecamatan),
  main = "Batas Kecamatan Kabupaten Madiun"
)

# ====================================
# 22. MENYAMAKAN CRS
# ====================================

# Mengubah sf menjadi SpatVector
kec <- vect(kecamatan)

# Menyamakan sistem koordinat
kec <- project(kec, crs(NDVI))

# Melihat hasil
plot(kec)

# ====================================
# 23. MENYIAPKAN RASTER
# ====================================

# Menyamakan grid raster awan
if (!same.crs(AWAN, NDVI)) {
  AWAN_fix <- project(AWAN, NDVI, method = "near")
} else {
  AWAN_fix <- resample(AWAN, NDVI, method = "near")
}

# Menggabungkan raster
indeks_zonal <- c(
  NDVI,
  NDBI,
  NDWI,
  AWAN_fix
)

names(indeks_zonal) <- c(
  "NDVI",
  "NDBI",
  "NDWI",
  "AWAN"
)
# ====================================
# 24. MENGHITUNG ZONAL STATISTICS
# ====================================

zonal <- data.frame(
  Kecamatan = kec$kecamatan
)

statistik <- list(
  Mean = mean,
  Minimum = min,
  Maximum = max,
  Median = median,
  SD = sd
)

for (nama in names(indeks_zonal)) {
  
  for (stat in names(statistik)) {
    
    hasil <- terra::extract(
      indeks_zonal[[nama]],
      kec,
      fun = statistik[[stat]],
      na.rm = TRUE
    )
    
    zonal[[paste(nama, stat, sep = "_")]] <- hasil[[2]]
  }
}

# Menampilkan hasil
View(zonal)
# ====================================
# 25. MENYIMPAN ZONAL STATISTICS
# ====================================

# Membuat folder output
dir.create("output", showWarnings = FALSE)

# Menyimpan hasil ke CSV
write.csv(
  zonal,
  "output/Zonal_Statistics_Madiun.csv",
  row.names = FALSE
)

# Memastikan file tersimpan
file.exists("output/Zonal_Statistics_Madiun.csv")

