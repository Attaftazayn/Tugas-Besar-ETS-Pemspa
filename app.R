# =============================================================================
# WebGIS Indeks Spektral Kabupaten & Kota Madiun
# -----------------------------------------------------------------------------
# Dashboard berbasis R (shiny + shinydashboard + leaflet) yang menampilkan:
#   1. Peta interaktif indeks spektral Sentinel-2 (NDVI, NDBI, NDWI, NDCI)
#   2. Tabel statistik zonal per kecamatan (sorting, filter, pagination)
#
# Prasyarat : folder Data/ (batas administrasi) dan output/ (raster + CSV)
# Menjalankan: shiny::runApp(".")  atau  Rscript app.R
# =============================================================================


# =============================================================================
# 1. MEMANGGIL LIBRARY
# =============================================================================

library(shiny)           # framework aplikasi web
library(shinydashboard)  # komponen dashboard (header, sidebar, body)
library(leaflet)         # peta interaktif
library(sf)              # data vektor (batas kecamatan)
library(raster)          # data raster (indeks spektral)
library(DT)              # tabel data interaktif
library(ggplot2)         # grafik batang pada tab statistik
library(plotly)          # versi interaktif grafik pada tab statistik

# Fungsi bantu murni (cari_file, normalisasi_nama) dipisahkan ke utils.R
# agar dapat diuji terpisah (lihat tests/).
source("utils.R")


# =============================================================================
# 2. KONFIGURASI PATH & METADATA INDEKS
# -----------------------------------------------------------------------------
# Semua data dimuat SEKALI di level global (di luar server), sehingga tidak
# dibaca ulang setiap kali ada pengguna baru membuka dashboard.
#
# Catatan: file batas administrasi di folder Data/ bernama "batas madiun"
# (tanpa ekstensi) sehingga dicari otomatis dengan pola nama "batas".
# =============================================================================

folder_data   <- "Data"
folder_output <- "output"

# cari_file() didefinisikan di utils.R (di-source di atas).

# Nama file batas administrasi & tabel statistik zonal
file_batas <- cari_file(folder_data, "^batas")
file_zonal <- cari_file(folder_output, "^Zonal_Statistics_Madiun\\.csv$")

# Metadata tiap indeks: nama file, label, palet peta, warna aksen (untuk chip
# & grafik), sebutan singkat, serta penjelasan bahasa awam pada modal "Tentang".
# Untuk menambah indeks lain cukup tambahkan satu baris di sini.
meta_indeks <- list(
  NDVI = list(file = "NDVI_madiun.tif",
              label = "NDVI - Vegetasi",
              palet = "YlGn",
              aksen = "#2e9e5b",
              singkat = "Vegetasi",
              info = paste0("Mengukur kerapatan dan kesehatan tumbuhan. Nilai tinggi ",
                            "(mendekati 1) berarti tutupan hijau rapat seperti hutan, ",
                            "kebun, dan sawah; nilai rendah menandakan lahan terbuka.")),
  NDBI = list(file = "NDBI_madiun.tif",
              label = "NDBI - Lahan Terbangun",
              palet = "YlOrRd",
              aksen = "#d9663d",
              singkat = "Bangunan",
              info = paste0("Menandai bangunan dan lahan terbangun. Nilai tinggi ",
                            "menunjukkan permukiman, kawasan industri, atau jalan; ",
                            "nilai rendah berarti vegetasi atau lahan kosong.")),
  NDWI = list(file = "NDWI_madiun.tif",
              label = "NDWI - Perairan",
              palet = "Blues",
              aksen = "#2f6fd0",
              singkat = "Perairan",
              info = paste0("Menandai keberadaan air. Nilai tinggi menunjukkan badan ",
                            "air seperti sungai, waduk, kolam, maupun sawah tergenang.")),
  NDCI = list(file = "NDCI_Cloud_Madiun.tif",
              label = "NDCI - Indeks Awan",
              palet = "YlGnBu",
              aksen = "#128ea0",
              singkat = "Awan",
              info = paste0("Menandai keberadaan awan pada citra. Nilai tinggi menunjukkan ",
                            "tutupan awan, sedangkan nilai rendah berarti permukaan daratan ",
                            "atau perairan yang relatif bebas awan."))
)

# Warna aksen tiap indeks sebagai named vector (dipakai grafik & kartu ringkasan)
palet_aksen <- vapply(meta_indeks, function(m) m$aksen, character(1))

# =============================================================================
# BATAS KELAS INDEKS (untuk tampilan klasifikasi)
# -----------------------------------------------------------------------------
# Peta bisa dilihat dalam dua mode:
#   - kontinu : warna mengikuti nilai indeks (default)
#   - kelas   : nilai dipecah menjadi kategori bertingkat yang lebih mudah
#               dibaca, misalnya "vegetasi jarang", "vegetasi rapat"
# Tiap indeks dipecah menjadi 4 kelas dengan batas yang lazim dipakai pada
# literatur indeks spektral. Batas bersifat (batas[i], batas[i+1]].
# =============================================================================

kelas_indeks <- list(
  NDVI = list(
    batas = c(-1, 0.2, 0.4, 0.6, 1),
    label = c("Non-vegetasi (< 0,2)",
              "Vegetasi jarang (0,2 - 0,4)",
              "Vegetasi sedang (0,4 - 0,6)",
              "Vegetasi rapat (> 0,6)"),
    warna = c("#d73027", "#f4a300", "#a6d96a", "#1a9641")),
  NDBI = list(
    batas = c(-1, -0.1, 0.1, 0.3, 1),
    label = c("Vegetasi / perairan (< -0,1)",
              "Lahan campuran (-0,1 - 0,1)",
              "Terbangun sedang (0,1 - 0,3)",
              "Terbangun rapat (> 0,3)"),
    warna = c("#1a9641", "#a6d96a", "#f4a300", "#d73027")),
  NDWI = list(
    batas = c(-1, -0.2, 0.2, 0.5, 1),
    label = c("Daratan kering (< -0,2)",
              "Lembap / tergenang (-0,2 - 0,2)",
              "Air dangkal (0,2 - 0,5)",
              "Air luas (> 0,5)"),
    warna = c("#a66a00", "#e8d08a", "#74a9cf", "#08306b")),
  NDCI = list(
    batas = c(-1, -0.5, -0.3, -0.1, 1),
    label = c("Awan sangat rendah (< -0,5)",
              "Awan rendah (-0,5 - -0,3)",
              "Awan sedang (-0,3 - -0,1)",
              "Awan tinggi (> -0,1)"),
    warna = c("#fff7bc", "#a1dab4", "#41b6c4", "#0c2c84"))
)

# Objek palet Leaflet (colorBin) untuk mode kelas. Warnanya berupa kategori
# tegas (bukan gradasi), sehingga peta lebih mudah dibaca per kelas.
palet_kelas <- Map(
  f = function(nama) {
    colorBin(
      palette  = kelas_indeks[[nama]]$warna,
      bins     = kelas_indeks[[nama]]$batas,
      na.color = "#00000000",
      alpha    = TRUE
    )
  },
  nama = names(kelas_indeks)
)

# Lengkapkan path raster (nama file di-escape agar titik .tif tidak dianggap
# sebagai wildcard pada pola pencarian)
file_indeks <- vapply(
  meta_indeks,
  function(m) cari_file(folder_output, paste0("^", gsub("\\.", "\\\\.", m$file), "$")),
  character(1)
)

# Pastikan semua file yang dibutuhkan tersedia sebelum aplikasi jalan
file_wajib <- c(batas = file_batas, zonal = file_zonal, file_indeks)
if (any(is.na(file_wajib)) || any(!file.exists(file_wajib))) {
  stop("File tidak ditemukan:\n  ",
       paste(file_wajib[is.na(file_wajib) | !file.exists(file_wajib)],
             collapse = "\n  "))
}

# Faktor agregasi raster saat ditampilkan di web:
#   2 -> resolusi tampilan 40 m (4 raster dikirim +/- 8 MB per sesi)
#   3 -> resolusi tampilan 60 m (lebih ringan lagi, +/- 4 MB per sesi)
faktor_agregasi <- 2


# =============================================================================
# 2b. KONFIGURASI BASEMAP CARTO
# -----------------------------------------------------------------------------
# Sejak 25 September 2026 tile raster CARTO (basemaps.cartocdn.com) hanya
# dilayani bila URL-nya menyertakan parameter ?key=... Tanpa key, yang muncul
# adalah gambar bertuliskan "API KEY REQUIRED". Karena itu basemap CARTO di
# bawah ini dibangun manual (tidak lagi memakai providers$CartoDB.* milik
# leaflet yang tanpa key).
#
# Key diambil dari environment variable CARTO_API_KEY bila ada; kalau tidak,
# dipakai key bawaan di bawah ini. Key basemap CARTO ini gratis (bukan kredensial
# akun) dan boleh dipakai di aplikasi non-komersial dengan atribusi tetap tampil.
# =============================================================================

carto_api_key <- Sys.getenv(
  "CARTO_API_KEY",
  unset = "cb1_4hsu_1_cbb8a8ccb279515c7a94faa8"
)

# Atribusi wajib: OpenStreetMap + CARTO (syarat pemakaian CARTO Basemaps)
atrib_carto <- paste0(
  '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>, ',
  '&copy; <a href="https://carto.com/attributions">CARTO</a>'
)

# Daftar gaya basemap CARTO yang dipakai (nama tampilan = kunci, style = nilai).
# Nama style mengikuti dokumentasi https://github.com/CartoDB/basemap-styles
carto_style <- c(
  "CARTO Positron"                = "light_all",             # terang, cocok untuk overlay
  "CARTO Positron Tanpa Label"    = "light_nolabels",        # terang tanpa nama tempat
  "CARTO Dark Matter"             = "dark_all",              # gelap, kontras untuk data
  "CARTO Dark Matter Tanpa Label" = "dark_nolabels",         # gelap tanpa nama tempat
  "CARTO Voyager"                 = "rastertiles/voyager"    # berwarna, jalan berkelas
)

# Fungsi bantu pembuat URL tile CARTO (sudah termasuk API key).
#   {s} = subdomain a-d, {r} = "@2x" pada layar retina (detectRetina)
url_carto <- function(style) {
  paste0("https://{s}.basemaps.cartocdn.com/", style,
         "/{z}/{x}/{y}{r}.png?key=", carto_api_key)
}

# Daftar basemap untuk layer control. Urutan pertama = basemap yang aktif
# saat aplikasi dibuka (CARTO Positron dipilih karena paling nyaman untuk
# membaca overlay raster di atasnya).
grup_basemap <- c(names(carto_style), "OpenStreetMap", "Esri World Imagery")


# =============================================================================
# 3. PRA-PROSES RASTER INDEKS (sekali di awal, bukan per sesi)
# -----------------------------------------------------------------------------
# Raster asli berukuran 2216 x 2207 sel (resolusi 20 m, UTM 49S) = 4,9 juta
# piksel per indeks. Bila langsung dikirim ke Leaflet, proyeksi + encoding PNG
# akan lambat dan berisiko melebihi batas ukuran (4 MB) bawaan addRasterImage.
#
# Solusinya, sekali di awal aplikasi kami:
#   a. turunkan resolusi 2x (faktor agregasi 2 -> 1108 x 1104 sel), DAN
#   b. reproject ke Web Mercator (EPSG:3857) sesuai sistem koordinat Leaflet,
#   semuanya dalam SATU langkah resampling saja (lebih hemat waktu).
# Hasilnya disimpan dalam objek global dan dipakai bersama oleh semua sesi.
# =============================================================================

baca_dan_praproses <- function(path, faktor = faktor_agregasi) {

  # Membaca metadata (nilai piksel baru dibaca saat di-resample)
  r <- raster(path)

  # Buat grid tujuan: proyeksi ke EPSG:3857 lalu diperkecil faktor agregasi
  grid_web <- projectExtent(r, crs = "EPSG:3857")
  grid_web <- raster(
    ncols = max(1L, round(ncol(grid_web) / faktor)),
    nrows = max(1L, round(nrow(grid_web) / faktor)),
    xmn = xmin(grid_web), xmx = xmax(grid_web),
    ymn = ymin(grid_web), ymx = ymax(grid_web),
    crs = "EPSG:3857"
  )

  # Resampling bilinear (cocok untuk nilai indeks yang kontinu)
  projectRaster(r, to = grid_web, method = "bilinear")
}

# Muat semua raster indeks (jumlahnya mengikuti isi meta_indeks)
raster_indeks <- lapply(file_indeks, baca_dan_praproses)

# Rentang nilai tiap indeks -> dipakai sebagai domain palet warna & legenda
rentang_indeks <- lapply(raster_indeks, function(r) {
  range(values(r), na.rm = TRUE)
})

# Objek palet Leaflet (colorNumeric). Palet dibuat sebagai FUNGSI agar
# addRasterImage memakai domain ini, bukan domain otomatis dari data.
# Warna transparan (#00000000) dipakai untuk piksel NA (di luar batas wilayah).
palet_indeks <- Map(
  f = function(nama, rentang) {
    colorNumeric(
      palette  = meta_indeks[[nama]]$palet,
      domain   = rentang,
      na.color = "#00000000",
      alpha    = TRUE
    )
  },
  nama    = names(raster_indeks),
  rentang = rentang_indeks
)


# =============================================================================
# 4. MEMUAT BATAS ADMINISTRASI (vektor)
# -----------------------------------------------------------------------------
# GeoJSON sudah dalam EPSG:4326 (lon/lat) sehingga siap dipakai Leaflet
# tanpa perlu transformasi. Isinya 21 kecamatan: Kota Madiun, Kabupaten
# Madiun, serta sebagian Magetan dan Ponorogo yang masuk ke dalam citra.
# =============================================================================

batas_kec <- st_read(file_batas, quiet = TRUE)

# Bersihkan geometri agar tidak ada poligon kosong / tidak valid
batas_kec <- batas_kec[!st_is_empty(batas_kec), ]
batas_kec <- st_make_valid(batas_kec)

# st_make_valid bisa menghasilkan campuran POLYGON / MULTIPOLYGON /
# GEOMETRYCOLLECTION. Leaflet hanya mau poligon, jadi paksa semuanya
# menjadi MULTIPOLYGON agar addPolygons tidak error.
batas_kec <- st_cast(batas_kec, "MULTIPOLYGON")

# Samakan sistem koordinat ke WGS84 (lon/lat) bila berbeda
epsg_batas <- st_crs(batas_kec)$epsg
if (is.null(epsg_batas) || is.na(epsg_batas) || epsg_batas != 4326) {
  batas_kec <- st_transform(batas_kec, 4326)
}

# Kolom untuk tooltip: pakai kolom "label" bila ada (berisi nama kecamatan,
# kabupaten/kota, dan provinsi), kalau tidak ada pakai nama kecamatan saja.
if ("label" %in% names(batas_kec)) {
  batas_kec$label_peta <- batas_kec$label
} else if ("kecamatan" %in% names(batas_kec)) {
  batas_kec$label_peta <- batas_kec$kecamatan
} else {
  batas_kec$label_peta <- as.character(seq_len(nrow(batas_kec)))
}


# =============================================================================
# 5. MEMUAT TABEL STATISTIK ZONAL
# =============================================================================

zonal_stats <- read.csv(file_zonal, stringsAsFactors = FALSE)


# =============================================================================
# 5b. GABUNG STATISTIK ZONAL KE ATRIBUT POLIGON
# -----------------------------------------------------------------------------
# Statistik dari CSV digabungkan ke atribut batas kecamatan agar bisa
# ditampilkan pada tooltip/popup. Dua kecamatan yang hanya terpotong di tepi
# citra (Bendo - Magetan, Jenangan - Ponorogo) tidak tercantum di CSV sehingga
# nilai statistiknya NA dan ditampilkan sebagai "n.a.".
# =============================================================================

# normalisasi_nama() didefinisikan di utils.R (di-source di atas).

kolom_stat <- c("NDVI_Mean", "NDVI_Minimum", "NDVI_Maximum", "NDVI_Median",
                "NDBI_Mean", "NDBI_Minimum", "NDBI_Maximum", "NDBI_Median",
                "NDWI_Mean", "NDWI_Minimum", "NDWI_Maximum", "NDWI_Median",
                "NDCI_Mean", "NDCI_Minimum", "NDCI_Maximum", "NDCI_Median")

zonal_join <- zonal_stats[, c("Kecamatan", kolom_stat)]
zonal_join$kec_join <- normalisasi_nama(zonal_join$Kecamatan)
batas_kec$kec_join  <- normalisasi_nama(batas_kec$kecamatan)

# Gabungkan hanya bila nama kecamatan di CSV unik
if (anyDuplicated(zonal_join$kec_join) == 0) {
  batas_kec <- merge(
    batas_kec,
    zonal_join[, c("kec_join", kolom_stat)],
    by = "kec_join",
    all.x = TRUE
  )
}


# =============================================================================
# 5c. TEKS INFORMATIF UNTUK LABEL, TOOLTIP, DAN POPUP
# -----------------------------------------------------------------------------
#   label_pendek : teks permanen di peta (nama kecamatan saja agar ringkas)
#   tooltip_kec  : muncul saat kursor mendarat di poligon (nama + statistik)
#   popup_kec    : muncul saat poligon diklik (info lengkap per indeks)
#   titik_label  : titik pusat kecamatan sebagai penempel label permanen
# =============================================================================

# Dua kecamatan (Bendo - Magetan, Jenangan - Ponorogo) berupa irisan nol-luas
# di tepi citra: setelah st_make_valid geometrinya tidak menyimpan koordinat
# berarti sehingga st_point_on_surface kosong. Karena tidak bisa digambar
# maupun diberi label, keduanya dikeluarkan dari peta agar konsisten.
crs_planar <- 32749   # UTM zona 49S (wilayah Madiun)
pusat_geom <- st_geometry(batas_kec) |>
  st_transform(crs_planar) |>
  st_point_on_surface() |>
  st_transform(4326)

sehat <- !st_is_empty(pusat_geom)
batas_kec  <- batas_kec[sehat, ]
pusat_geom <- pusat_geom[sehat]

# Nama kabupaten/kota yang mudah dibaca
kab_label <- ifelse(
  batas_kec$kab_kota == "Kota Madiun",
  "Kota Madiun",
  paste0("Kabupaten ", batas_kec$kab_kota)
)

# Luas wilayah tiap kecamatan (hektar), dihitung pada proyeksi UTM 49S
# (crs_planar) agar hasil luas akurat dan tidak bergantung pada satuan derajat.
batas_kec$luas_ha <- as.numeric(
  st_area(st_transform(batas_kec, crs_planar))
) / 10000

# Format angka 3 desimal; "n.a." bila data tidak ada
fmt3 <- function(x) ifelse(is.na(x), "n.a.", sprintf("%.3f", x))

# Format angka 1 desimal; "n.a." bila data tidak ada
fmt1 <- function(x) ifelse(is.na(x), "n.a.", sprintf("%.1f", x))

# Baris teks ringkas satu indeks untuk tooltip (nilai mean saja)
baris_tooltip <- function(pr) {
  if (all(is.na(batas_kec[[paste0(pr, "_Mean")]]))) return(rep("", nrow(batas_kec)))
  paste0(meta_indeks[[pr]]$label, ": <b>", fmt3(batas_kec[[paste0(pr, "_Mean")]]), "</b>")
}

# Baris teks lengkap satu indeks untuk popup (mean, median, min, max, sd)
baris_popup <- function(pr) {
  if (all(is.na(batas_kec[[paste0(pr, "_Mean")]]))) return(rep("", nrow(batas_kec)))
  paste0(
    "<b>", meta_indeks[[pr]]$label, "</b>: mean ",
    fmt3(batas_kec[[paste0(pr, "_Mean")]]), "<br>",
    "&nbsp;&nbsp;median ", fmt3(batas_kec[[paste0(pr, "_Median")]]),
    " &nbsp;|&nbsp; sd ", fmt3(batas_kec[[paste0(pr, "_SD")]]), "<br>",
    "&nbsp;&nbsp;min ", fmt3(batas_kec[[paste0(pr, "_Minimum")]]),
    " | max ", fmt3(batas_kec[[paste0(pr, "_Maximum")]])
  )
}

prs_aktif <- intersect(c("NDVI", "NDBI", "NDWI", "NDCI"), names(meta_indeks))

label_pendek <- batas_kec$kecamatan
tooltip_kec   <- paste0("<b>", label_pendek, "</b><br>", kab_label)
popup_kec     <- paste0("<b>", label_pendek, "</b><br>", kab_label,
                        "<br>Luas wilayah: ", fmt1(batas_kec$luas_ha), " ha",
                        "<hr style='margin:5px 0'>")
for (pr in prs_aktif) {
  tooltip_kec <- paste0(tooltip_kec, "<br>", baris_tooltip(pr))
  popup_kec   <- paste0(popup_kec, "<br>", baris_popup(pr))
}

# PENTING: htmltools::HTML() MENGGABUNGKAN sebuah vektor menjadi SATU string
# (length 1) sehingga bila dipakai langsung, semua kecamatan mendapat teks yang
# sama. Karena itu setiap teks dibungkus per-elemen menjadi DAFTAR string HTML.
tooltip_html <- lapply(tooltip_kec, htmltools::HTML)
popup_html   <- lapply(popup_kec, htmltools::HTML)

# Titik pusat tiap kecamatan sebagai penempel label nama permanen
titik_label <- st_sf(
  label_pendek = label_pendek,
  geometry     = pusat_geom
)


# =============================================================================
# 5d. TABEL RINGKAS UNTUK TAB STATISTIK
# -----------------------------------------------------------------------------
# Satu tabel rapi berisi nama kecamatan, wilayah (kabupaten/kota), dan lima
# nilai statistik (rata-rata, minimum, maksimum, median, simpangan baku) untuk
# setiap indeks. Wilayah dipetakan dari poligon lewat pencocokan nama.
# =============================================================================

# Peta nama kecamatan -> wilayah (kabupaten/kota), dari poligon yang valid
peta_wilayah <- setNames(kab_label, normalisasi_nama(batas_kec$kecamatan))

# Peta nama kecamatan -> luas (ha), dari poligon yang valid
peta_luas <- setNames(batas_kec$luas_ha, normalisasi_nama(batas_kec$kecamatan))

# Kolom statistik lengkap (termasuk simpangan baku) diambil dari CSV zonal
kolom_ringkas <- unlist(lapply(prs_aktif, function(p)
  paste0(p, "_", c("Mean", "Minimum", "Maximum", "Median", "SD"))))

zonal_rapi <- data.frame(
  Kecamatan = zonal_stats$Kecamatan,
  Wilayah   = unname(peta_wilayah[normalisasi_nama(zonal_stats$Kecamatan)]),
  Luas_ha   = unname(peta_luas[normalisasi_nama(zonal_stats$Kecamatan)]),
  stringsAsFactors = FALSE
)
for (kol in kolom_ringkas) zonal_rapi[[kol]] <- zonal_stats[[kol]]


# =============================================================================
# 6. UI (shinydashboard)
# =============================================================================

ui <- dashboardPage(

  # --- 6.1 Header dashboard ---
  dashboardHeader(
    title = tags$span(
      class = "brand",
      "WebGIS Indeks Spektral Kota Madiun dan Kab. Madiun"
    ),
    titleWidth = 470,
    tags$li(
      class = "dropdown",
      actionLink("btn_tentang", "Tentang",
                 class = "btn-tentang", title = "Tentang aplikasi")
    )
  ),

  # --- 6.2 Sidebar berisi menu navigasi ---
  dashboardSidebar(
    width = 250,
    sidebarMenu(
      id = "menu_samping",
      menuItem("Peta Interaktif",
               tabName = "peta",
               icon = icon("map-marked-alt")),
      menuItem("Statistik Zonal",
               tabName = "statistik",
               icon = icon("chart-bar"))
    ),
    tags$div(
      class = "sidebar-note",
      tags$div(class = "sidebar-note-title", "Indeks Spektral Sentinel-2"),
      tags$div("Kabupaten & Kota Madiun dan sekitarnya"),
      tags$div(
        class = "sidebar-note-creator",
        tags$b("Dibuat oleh:"),
        tags$div("Abul Fahmi Attaftazani \u2013 5016241048"),
        tags$div("Sabrina Sandra RA \u2013 5016241061")
      )
    )
  ),

  # --- 6.3 Body dashboard ---
  dashboardBody(

    tags$head(
      # Jenis huruf modern (bila tidak ada koneksi, otomatis pakai huruf sistem)
      tags$link(rel = "stylesheet",
                href = "https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap"),
      tags$style(HTML("
        :root { --ink:#17233d; --muted:#6b7686; --line:#e5eaf4; --accent:#2f6fd0; }

        body, .main-header, .main-sidebar, .content-wrapper,
        h1, h2, h3, h4, h5, .box-title, .small-box, table { font-family:'Inter','Segoe UI',system-ui,sans-serif; }

        .content-wrapper { background:#eef1f8 !important; margin-top:50px; }
        .content { padding:16px 18px; }

        /* ---- Header & sidebar ---- */
        /* Warna gradien dipasang pada header (bukan per elemen) agar TIDAK ada
           batas/jahitan warna di antara area judul dan area kanan. */
        .main-header { background:linear-gradient(100deg,#152340,#2f5596) !important;
          position:fixed !important; top:0; right:0; left:0; z-index:1030; }
        .main-header .logo, .main-header .navbar { background:transparent !important; }
        .main-header .navbar { position:static !important; }
        .main-header .logo { font-weight:700; padding-left:66px; }
        /* Garis triple (toggle sidebar) dipindah ke pojok kiri header */
        .main-header .sidebar-toggle {
          position:absolute; left:0; top:0; height:50px; width:50px;
          display:flex; align-items:center; justify-content:center;
          padding:0 !important; color:#fff !important; z-index:1040;
          background:rgba(255,255,255,.10) !important;
        }
        .main-header .sidebar-toggle:hover { background:rgba(255,255,255,.22) !important; }
        .main-header .sidebar-toggle:before { font-size:16px; }
        .brand { display:flex; align-items:center; gap:9px; font-weight:700; letter-spacing:.2px; font-size:13px; white-space:nowrap; }
        .brand-mark { display:inline-flex; width:26px; height:26px; border-radius:8px;
          background:rgba(255,255,255,.16); align-items:center; justify-content:center; font-size:13px; }
        .main-sidebar { background:#152340 !important;
          position:fixed !important; top:0; bottom:0; overflow-y:auto; z-index:1020; }
        .sidebar-menu > li > a { font-weight:500; font-size:14px; }
        .sidebar-menu > li > a:hover { background:#1e2f52 !important; }
        .sidebar-menu > li.active > a { background:#27406f !important; border-left:3px solid #4fc3f7 !important; }
        .sidebar-note { padding:13px 15px; margin:14px 12px; border-radius:12px;
          background:rgba(255,255,255,.06); color:#c8d4ea; font-size:12px; line-height:1.5; }
        .sidebar-note-title { color:#fff; font-weight:700; margin-bottom:2px; }
        .sidebar-note-small { margin-top:8px; color:#8fa3c8; font-size:11px; }
        .sidebar-note-creator { margin-top:10px; padding-top:9px; border-top:1px dashed rgba(255,255,255,.15);
          color:#8fa3c8; font-size:11px; line-height:1.6; }
        .sidebar-note-creator b { color:#c8d4ea; display:block; margin-bottom:3px; font-size:11.5px; }
        .app-footer { margin-top:6px; padding:14px 18px; text-align:center; font-size:12.5px;
          color:#6b7686; background:#eef1f8; border-top:1px solid var(--line); }
        .app-footer b { color:#33405a; }

        /* ---- Judul halaman & chip ---- */
        .page-head { display:flex; flex-wrap:wrap; justify-content:space-between;
          align-items:center; gap:10px; margin:2px 0 14px; }
        .page-head h2 { margin:0; font-size:21px; font-weight:700; color:var(--ink); }
        .page-head p { margin:4px 0 0; color:var(--muted); font-size:13px; }
        .chip-row { display:flex; gap:8px; flex-wrap:wrap; }
        .chip { display:inline-flex; align-items:center; gap:7px; background:#fff; border:1px solid var(--line);
          border-radius:999px; padding:5px 12px; font-size:12.5px; font-weight:600; color:#33405a;
          box-shadow:0 2px 6px rgba(20,40,80,.05); }
        .dot { width:10px; height:10px; border-radius:50%; display:inline-block; }

        /* ---- Kartu & kotak ---- */
        .box { border-radius:16px !important; box-shadow:0 6px 22px rgba(20,40,80,.08) !important;
          border-top:none !important; }
        .box-header { border-bottom:1px solid var(--line); }
        .box-title { font-weight:600; color:var(--ink); }
        .small-box { border-radius:16px !important; box-shadow:0 8px 20px rgba(20,40,80,.12); }
        .small-box h3 { font-weight:700; }
        .small-box p { font-weight:500; opacity:.95; }
        .help-mini { color:var(--muted); font-size:11.5px; line-height:1.5; margin-top:4px; }

        /* ---- Peta ---- */
        .map-card { position:relative; background:#fff; border-radius:18px; box-shadow:0 8px 26px rgba(20,40,80,.12);
          padding:8px; height:calc(100vh - 158px); }
        .map-card .shiny-leaflet-output, .map-card .leaflet-container { height:100% !important; }
        .map-card .leaflet-container { border-radius:14px; }
        .map-help { position:absolute; top:20px; left:58px; z-index:600;
          background:rgba(255,255,255,.97); border-radius:14px; width:250px;
          box-shadow:0 10px 26px rgba(20,40,80,.18); padding:12px 14px;
          color:#33405a; font-size:12.5px; line-height:1.5; }
        .map-help h4 { margin:0 0 6px; font-size:13.5px; color:#152340; }
        .map-help p { margin:0 0 7px; }

        /* ---- Kontrol Leaflet ---- */
        .leaflet-control-layers { border-radius:14px !important; border:none !important;
          box-shadow:0 8px 22px rgba(20,40,80,.18) !important; padding:10px 12px !important; font-size:13px !important; }
        .leaflet-control-layers-base label, .leaflet-control-layers-overlays label { margin:3px 0; }
        .leaflet-control.legend { border-radius:14px !important; font-size:12.5px;
          box-shadow:0 8px 22px rgba(20,40,80,.18) !important; padding:10px 12px !important; }
        .leaflet-control-scale-line { border-radius:6px; background:rgba(255,255,255,.85); }
        .map-help { background:rgba(255,255,255,.97); border-radius:14px; width:234px;
          box-shadow:0 10px 26px rgba(20,40,80,.18); padding:12px 14px;
          color:#33405a; font-size:12.5px; line-height:1.5; }
        .map-help h4 { margin:0 0 6px; font-size:13.5px; color:#152340; }
        .map-help p { margin:0 0 7px; }
        .map-help .chip { padding:3px 9px; margin:0 4px 4px 0; box-shadow:none; }
        .map-help .chip .dot { width:9px; height:9px; }

        /* ---- Label nama kecamatan yang selalu tampil ---- */
        .label-kec-permanen { background:transparent !important; border:none !important; box-shadow:none !important;
          color:#fff !important; font-size:12px; font-weight:700;
          text-shadow:0 1px 2px rgba(0,0,0,.95), 0 0 5px rgba(0,0,0,.9); white-space:nowrap; }

        /* ---- Tabel DT ---- */
        .dataTables_wrapper { font-size:13.5px; }
        table.dataTable thead th { background:#f2f5fb !important; color:#33405a !important;
          font-weight:600; border-bottom:2px solid #dde5f3 !important; }
        table.dataTable tbody td { border-bottom:1px solid #eef1f8 !important; }
        table.dataTable.hover tbody tr:hover { background:#f0f5ff !important; }
        .dataTables_wrapper .dt-buttons .btn { border-radius:9px; border:1px solid var(--line);
          font-weight:600; color:#33405a; }
        .dataTables_filter input, .dataTables_length select { border-radius:9px !important;
          border:1px solid var(--line) !important; }
        caption { caption-side:top; color:var(--muted); font-size:12.5px; padding-bottom:8px; }

        /* ---- Tab panduan ---- */
        .card { background:#fff; border-radius:16px; box-shadow:0 6px 22px rgba(20,40,80,.08);
          padding:16px 18px; height:100%; margin-bottom:14px; }
        .card-head { display:flex; align-items:center; gap:9px; font-size:15px;
          font-weight:700; color:var(--ink); margin-bottom:6px; }
        .card p { color:var(--muted); font-size:13px; line-height:1.6; margin:0; }
        .step-list { color:#33405a; font-size:13.5px; line-height:1.95; margin:0; padding-left:18px; }

        /* ---- Tombol Tentang pada header ---- */
        .main-header .dropdown { height:50px; display:flex; align-items:center; }
        .main-header .dropdown .action-button { display:flex; align-items:center; height:50px;
          padding:0 18px; color:#fff !important; font-size:13.5px; font-weight:600;
          border-left:1px solid rgba(255,255,255,.14); border-radius:0 !important; }
        .main-header .dropdown .action-button .action-label { margin-left:6px; }
        .main-header .dropdown .action-button:hover { background:rgba(255,255,255,.16); text-decoration:none; }

        /* ---- Selubung pemuatan (spinner) sampai peta siap ---- */
        #splash { position:fixed; top:50px; left:0; right:0; bottom:0; z-index:3000;
          background:#eef1f8; display:flex; align-items:center; justify-content:center;
          transition:opacity .45s ease; opacity:1; }
        #splash.sudah { opacity:0; pointer-events:none; }
        .splash-box { text-align:center; }
        .splash-teks { margin-top:14px; color:var(--muted); font-size:13.5px; }
        .spinner { width:44px; height:44px; margin:0 auto; border-radius:50%;
          border:4px solid #d7e0f0; border-top-color:#2f6fd0;
          animation:putar .9s linear infinite; }
        @keyframes putar { to { transform:rotate(360deg); } }

        /* ---- Tampilan pada layar kecil (ponsel & tablet) ---- */
        @media (max-width: 767px) {
          .main-header .logo { padding-left:46px; }
          .main-header .brand { font-size:11.5px; letter-spacing:0; }
          .main-header .dropdown .action-button { padding:0 13px; font-size:12.5px; }
          .content { padding:12px 8px; }
          .page-head h2 { font-size:18px; }
          .page-head p { font-size:12.5px; }
          .map-card { height:calc(100vh - 240px); min-height:320px; }
          .box { border-radius:12px !important; }
          .small-box h3 { font-size:25px; }
          .small-box p { font-size:11.5px; }
          table.dataTable { font-size:12px; }
          .leaflet-control-layers { max-width:175px; font-size:11.5px !important; }
          .leaflet-control.legend { font-size:11.5px; }
        }
        @media (min-width: 768px) and (max-width: 991px) {
          .main-header .brand { font-size:12px; }
          .map-card { height:calc(100vh - 195px); }
        }
      "))
    ),

    # Indeks spektral (NDVI/NDBI/NDWI/NDCI) hanya boleh menyala SATU per satu.
    # Listener ini bekerja pada kontrol layer Leaflet: setiap kali kotak indeks
    # dicentang, kotak indeks lain otomatis di-uncheck (lewat .click() agar
    # status & event Leaflet tetap sinkron). "Batas Kecamatan" dan "Nama
    # Kecamatan" TIDAK termasuk, jadi tetap bisa on/off bebas.
    tags$script(HTML(sprintf(
      "var INDEKS_LAYER = [%s];
       document.addEventListener('change', function(e){
         var t = e.target;
         if (!t || t.type !== 'checkbox' || !t.checked) return;
         var tlab = t.closest('label');
         var lbl = tlab ? tlab.textContent.trim() : '';
         if (INDEKS_LAYER.indexOf(lbl) === -1) return;
         document.querySelectorAll('.leaflet-control-layers input[type=checkbox]').forEach(function(cb){
           var lab = cb.closest('label');
           var l = lab ? lab.textContent.trim() : '';
           if (cb !== t && cb.checked && INDEKS_LAYER.indexOf(l) !== -1) cb.click();
         });
       });",
      paste(sprintf("'%s'", names(meta_indeks)), collapse = ", ")
    ))),

    # ---- Selubung pemuatan (spinner) sampai peta siap ditampilkan ----
    tags$div(
      id = "splash",
      tags$div(class = "splash-box",
               tags$div(class = "spinner"),
               tags$div(class = "splash-teks", "Menyiapkan peta indeks spektral…"))
    ),
    tags$script(HTML("
      (function(){
        var sp = document.getElementById('splash');
        if(!sp) return;
        var t = null;
        var selesai = function(){
          if(sp.classList.contains('sudah')) return;
          sp.classList.add('sudah');
          if(t) clearInterval(t);
          setTimeout(function(){ sp.style.display='none'; }, 450);
        };
        var siap = function(){ return !!document.querySelector('.leaflet-container .leaflet-pane'); };
        if (siap()) { selesai(); return; }
        t = setInterval(function(){ if (siap()) selesai(); }, 120);
        setTimeout(selesai, 12000);   // jangan biarkan pengguna menunggu terlalu lama
      })();
    ")),

    tabItems(

      # ---------- TAB 1: PETA INTERAKTIF ----------
      tabItem(
        tabName = "peta",
        tags$div(
          class = "page-head",
          tags$div(
            tags$h2("Peta Indeks Spektral"),
            tags$p("Citra Sentinel-2 · Kabupaten & Kota Madiun dan sekitarnya")
          ),
          tags$div(
            class = "chip-row",
            lapply(names(meta_indeks), function(k) {
              m <- meta_indeks[[k]]
              tags$span(class = "chip",
                        tags$span(class = "dot", style = paste0("background:", m$aksen)),
                        m$singkat)
            })
          )
        ),
        tags$div(
          class = "map-toolbar",
          checkboxInput(
            "tampilkan_kelas", "Tampilkan sebagai kelas (klasifikasi)",
            value = FALSE
          ),
          tags$span(class = "help-mini",
                    "Nilai indeks dipecah menjadi kategori berwarna bertingkat; ",
                    "legenda menyesuaikan otomatis.")
        ),
        tags$div(
          class = "map-card",
          leafletOutput("peta", height = "100%")
        )
      ),

      # ---------- TAB 2: STATISTIK ZONAL ----------
      tabItem(
        tabName = "statistik",
        tags$div(
          class = "page-head",
          tags$div(
            tags$h2("Statistik Zonal per Kecamatan"),
            tags$p("Pilih indeks, lihat peringkatnya, lalu telusuri angka rincinya.")
          )
        ),

        # Kartu ringkasan besar (KPI) yang berubah mengikuti pilihan
        fluidRow(
          valueBoxOutput("kpi_rata",   width = 3),
          valueBoxOutput("kpi_tinggi", width = 3),
          valueBoxOutput("kpi_rendah", width = 3),
          valueBoxOutput("kpi_jumlah", width = 3)
        ),

        fluidRow(
          box(
            title = "Pilihan tampilan", width = 3, solidHeader = FALSE,
            selectInput(
              "pilih_indeks", "Indeks spektral",
              choices = setNames(names(meta_indeks),
                                 vapply(meta_indeks, function(m) m$label, character(1))),
              selected = "NDVI"
            ),
            selectInput(
              "pilih_wilayah", "Wilayah",
              choices = c("Semua wilayah"    = "Semua",
                          "Kota Madiun"      = "Kota Madiun",
                          "Kabupaten Madiun" = "Kabupaten Madiun"),
              selected = "Semua"
            ),
            sliderInput(
              "rentang_nilai", "Saring nilai rata-rata",
              min = -1, max = 1, value = c(-1, 1), step = 0.01, width = "100%"
            ),
            tags$div(class = "help-mini",
                     "Grafik, tabel, dan sorotan peta mengikuti pilihan ini. ",
                     "Klik batang atau baris tabel untuk menyorot kecamatan.")
          ),
          box(
            title = "Peringkat rata-rata tiap kecamatan", width = 9,
            plotlyOutput("grafik_zonal", height = "380px")
          )
        ),

        fluidRow(
          box(
            title = "Tabel rinci", width = 12,
            DTOutput("tabel_zonal")
          )
        )
      )
    ),

    tags$footer(
      class = "app-footer",
      tags$span("Dibuat oleh: "),
      tags$b("Abul Fahmi Attaftazani (NRP: 5016241048)"),
      " \u00b7 ",
      tags$b("Sabrina Sandra RA (NRP: 5016241061)")
    )
  ),

  title = "WebGIS Indeks Spektral Kota Madiun dan Kab. Madiun",
  skin  = "blue"
)


# =============================================================================
# 7. SERVER
# =============================================================================

server <- function(input, output, session) {

  # -------------------------------------------------------------------------
  # 7.1 Peta dasar (renderLeaflet) - dieksekusi SEKALI per sesi
  # -------------------------------------------------------------------------
  output$peta <- renderLeaflet({

    # Bangun peta dasar
    peta <- leaflet(options = leafletOptions(
      minZoom = 8,
      maxZoom = 18,
      zoomControl = TRUE
    ))

    # --- 7.1.0 Basemap ---
    # a) Basemap CARTO (perlu API key, lihat bagian 2b)
    for (grup_bm in names(carto_style)) {
      peta <- peta %>%
        addTiles(
          urlTemplate = url_carto(carto_style[[grup_bm]]),
          group       = grup_bm,
          attribution = atrib_carto,
          options     = tileOptions(
            subdomains   = "abcd",     # {s} -> a/b/c/d.basemaps.cartocdn.com
            detectRetina = TRUE,       # {r} -> "@2x" pada layar retina
            maxZoom      = 20
          )
        )
    }

    # b) Basemap tambahan yang tidak memerlukan API key
    peta <- peta %>%
      addTiles(
        group = "OpenStreetMap",
        attribution = '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
      ) %>%
      addProviderTiles(providers$Esri.WorldImagery, group = "Esri World Imagery")

    # --- 7.1.1 Overlay raster indeks spektral ---
    # Ditambahkan lewat perulangan agar jumlah layer mengikuti meta_indeks.
    # project = FALSE karena raster sudah diproyeksikan ke EPSG:3857 saat
    # aplikasi dimulai (lihat bagian 3) -> jauh lebih ringan.
    for (nama in names(raster_indeks)) {
      peta <- peta %>%
        addRasterImage(
          x        = raster_indeks[[nama]],
          colors   = palet_indeks[[nama]],
          project  = FALSE,
          group    = nama,
          opacity  = 0.85,
          layerId  = nama,
          maxBytes = 12 * 1024^2,  # batas 12 MB (bawaan Leaflet hanya 4 MB)
          method   = "bilinear"    # interpolasi halus -> pola kotak berkurang
        )
    }

    # --- 7.1.2 Batas kecamatan, layer control, legenda, dan fokus wilayah ---
    peta <- peta %>%

      # Batas kecamatan: hanya garis tepi (tanpa isi).
      # label   = tooltip sebelum diklik (nama + statistik rata-rata)
      # popup   = info lengkap saat diklik
      addPolygons(
        data        = batas_kec,
        group       = "Batas Kecamatan",
        fill        = FALSE,          # tidak ada warna isi
        color       = "#FFFFFF",      # warna garis batas
        weight      = 2,
        opacity     = 1,
        dashArray   = "4 4",
        label       = tooltip_html,
        popup       = popup_html,
        highlightOptions = highlightOptions(
          weight = 4,
          color = "#2E86C1",
          bringToFront = TRUE
        )
      ) %>%

      # Label nama kecamatan yang SELALU tampil, tanpa perlu klik/hover.
      # Titik penempel = st_point_on_surface (pusat poligon).
      addLabelOnlyMarkers(
        data  = titik_label,
        label = ~label_pendek,
        labelOptions = labelOptions(
          noHide    = TRUE,
          textOnly  = TRUE,
          direction = "center",
          className = "label-kec-permanen",
          style     = list("pointer-events" = "none", "z-index" = "500")
        ),
        group = "Nama Kecamatan"
      ) %>%

      # Tampilkan NDVI saja di awal, indeks lain disembunyikan
      hideGroup(setdiff(names(meta_indeks), "NDVI")) %>%

      # Pengontrol basemap + toggle overlay
      addLayersControl(
        baseGroups = grup_basemap,
        overlayGroups = c("Nama Kecamatan", names(meta_indeks), "Batas Kecamatan"),
        options = layersControlOptions(collapsed = FALSE, position = "topright")
      ) %>%

      # Legenda awal (akan diganti otomatis saat layer berganti)
      addLegend(
        position  = "bottomright",
        pal       = palet_indeks$NDVI,
        values    = rentang_indeks$NDVI,
        title     = meta_indeks$NDVI$label,
        labFormat = labelFormat(digits = 2),
        opacity   = 0.9
      ) %>%

      # Skala jarak di pojok kiri bawah (informasi ukuran/luas wilayah)
      addScaleBar(position = "bottomleft") %>%

      # Pusatkan dan zoom otomatis ke wilayah Kabupaten & Kota Madiun
      fitBounds(lng1 = st_bbox(batas_kec)[["xmin"]],
                lat1 = st_bbox(batas_kec)[["ymin"]],
                lng2 = st_bbox(batas_kec)[["xmax"]],
                lat2 = st_bbox(batas_kec)[["ymax"]])

    peta
  })


  # -------------------------------------------------------------------------
  # 7.2 Legenda dinamis - menyesuaikan layer raster yang sedang aktif
  # -------------------------------------------------------------------------
  # input$peta_groups berisi daftar group yang sedang tampil di peta, sehingga
  # setiap kali user mencentang / membuka centang layer, server menerima
  # pemberitahuan dan legenda diganti dengan palet milik layer tersebut.
  #
  # Prioritas legenda:
  #   1. layer yang BARU dicentang     -> legenda langsung menunjuk layer itu
  #   2. bila layer legenda dimatikan  -> jatuh ke layer raster berikutnya
  #   3. bila tidak ada raster aktif   -> legenda disembunyikan
  # -------------------------------------------------------------------------

  state <- reactiveValues(
    grup_lama = character(0),   # daftar group pada pemberitahuan sebelumnya
    legenda   = "NDVI"          # layer yang sedang menjadi acuan legenda
  )

  # Gambar ulang legenda sesuai mode tampilan (kontinu / kelas) dan indeks.
  # Dipakai oleh pengamat pergantian layer (7.2) maupun sakelar klasifikasi.
  gambar_legenda <- function(acuan) {

    proxy <- leafletProxy("peta") %>% clearControls()   # hapus legenda lama
    if (is.null(acuan)) return(invisible(NULL))

    if (isTRUE(input$tampilkan_kelas)) {
      # Mode kelas: legenda berupa kategori tegas dengan nama kelasnya
      k <- kelas_indeks[[acuan]]
      proxy %>% addLegend(
        position = "bottomright",
        colors   = k$warna,
        labels   = k$label,
        title    = meta_indeks[[acuan]]$label,
        opacity  = 0.9
      )
    } else {
      # Mode kontinu: gradasi warna seperti semula
      proxy %>% addLegend(
        position  = "bottomright",
        pal       = palet_indeks[[acuan]],
        values    = rev(rentang_indeks[[acuan]]),
        title     = meta_indeks[[acuan]]$label,
        labFormat = labelFormat(digits = 2),
        opacity   = 0.9,
        decreasing = TRUE
      )
    }

    invisible(NULL)
  }

  observeEvent(input$peta_groups, {

    grup <- input$peta_groups
    if (is.null(grup)) grup <- character(0)

    raster_aktif <- intersect(names(meta_indeks), grup)

    # Layer raster yang baru saja dinyalakan pengguna
    grup_baru <- intersect(raster_aktif, setdiff(grup, state$grup_lama))

    acuan <- if (length(grup_baru) > 0) {
      grup_baru[1]                                  # ikuti layer terakhir aktif
    } else if (state$legenda %in% raster_aktif) {
      state$legenda                                 # legenda tetap relevan
    } else if (length(raster_aktif) > 0) {
      raster_aktif[1]                               # fallback ke raster lain
    } else {
      NULL                                          # tidak ada raster aktif
    }

    state$grup_lama <- grup

    # Hanya gambar ulang bila acuan legenda benar-benar berubah
    if (identical(acuan, state$legenda)) return()
    state$legenda <- acuan

    gambar_legenda(acuan)

    # Catatan: clearControls() hanya menghapus legenda, sedangkan
    # layers control (basemap/overlay) TIDAK ikut terhapus, jadi
    # pengguna tetap bisa mencentang layer seperti biasa.

  }, ignoreNULL = FALSE)


  # -------------------------------------------------------------------------
  # 7.2b Mode klasifikasi - ganti warna raster & legenda menjadi kategori
  # -------------------------------------------------------------------------
  # Raster ditambah ulang lewat proxy memakai palet sesuai mode, lalu
  # visibilitas layer dikembalikan seperti semula (yang dicentang tetap tampil).
  observeEvent(input$tampilkan_kelas, {

    kelas_mode <- isTRUE(input$tampilkan_kelas)
    warna_baru <- if (kelas_mode) palet_kelas else palet_indeks

    grup <- input$peta_groups
    if (is.null(grup)) grup <- character(0)
    raster_aktif <- intersect(names(meta_indeks), grup)

    for (nama in names(raster_indeks)) {
      leafletProxy("peta") %>%
        removeImage(nama) %>%
        addRasterImage(
          x        = raster_indeks[[nama]],
          colors   = warna_baru[[nama]],
          project  = FALSE,
          group    = nama,
          opacity  = 0.85,
          layerId  = nama,
          maxBytes = 12 * 1024^2,
          method   = "bilinear"
        )
    }

    # Pulihkan visibilitas layer seperti sebelum diganti
    proxy <- leafletProxy("peta")
    proxy %>% hideGroup(setdiff(names(meta_indeks), raster_aktif))
    if (length(raster_aktif) > 0) proxy %>% showGroup(raster_aktif)

    # Legenda harus selalu mengikuti mode terbaru
    gambar_legenda(state$legenda)

  }, ignoreInit = TRUE)

  # -------------------------------------------------------------------------
  # 7.3 Statistik zonal - kartu ringkasan, grafik peringkat, dan tabel rinci
  # -------------------------------------------------------------------------

  # Data terfilter menurut pilihan wilayah (reaktif)
  data_wilayah <- reactive({
    d <- zonal_rapi
    if (!is.null(input$pilih_wilayah) && input$pilih_wilayah != "Semua") {
      d <- d[d$Wilayah == input$pilih_wilayah, , drop = FALSE]
    }
    d
  })

  # Data terfilter wilayah + rentang nilai pada slider (reaktif)
  data_zonal <- reactive({
    d  <- data_wilayah()
    pr <- input$pilih_indeks
    if (is.null(pr) || !nzchar(pr)) return(d)
    v <- d[[paste0(pr, "_Mean")]]
    if (!is.null(input$rentang_nilai) && length(v) > 0) {
      batas <- input$rentang_nilai
      d <- d[!is.na(v) & v >= batas[1] & v <= batas[2], , drop = FALSE]
    }
    d
  })

  # Rentang slider otomatis menyesuaikan indeks & wilayah yang dipilih
  observe({
    req(input$pilih_indeks, input$pilih_wilayah)
    v <- data_wilayah()[[paste0(input$pilih_indeks, "_Mean")]]
    v <- v[is.finite(v)]
    if (length(v) == 0) return()
    lo <- floor(min(v) * 100) / 100
    hi <- ceiling(max(v) * 100) / 100
    updateSliderInput(session, "rentang_nilai", min = lo, max = hi,
                      value = c(lo, hi), step = 0.01)
  })

  # Sorot satu kecamatan di peta (dipakai oleh klik grafik & baris tabel)
  sorot_kecamatan <- function(kec) {
    if (is.null(kec) || length(kec) == 0 || !nzchar(kec)) return()
    sel <- batas_kec[normalisasi_nama(batas_kec$kecamatan) ==
                       normalisasi_nama(kec), , drop = FALSE]
    proxy <- leafletProxy("peta") %>% clearGroup("Sorotan")
    # clearGroup hanya menghapus bila grup sudah pernah dikirim; hapus layerId
    # juga agar highlight sebelumnya benar-benar hilang.
    proxy <- tryCatch(proxy %>% removeShape("sorotan_kec"), error = function(e) proxy)
    if (nrow(sel) == 0) return()
    proxy %>% addPolygons(
      data        = sel,
      group       = "Sorotan",
      layerId     = "sorotan_kec",
      color       = "#ffb703",
      weight      = 4,
      opacity     = 1,
      fillColor   = "#ffb703",
      fillOpacity = 0.18
    )

    # Perbesar tampilan peta ke kecamatan terpilih agar sorotan langsung jelas.
    bb <- st_bbox(sel)
    proxy %>% flyToBounds(
      lng1 = bb[["xmin"]], lat1 = bb[["ymin"]],
      lng2 = bb[["xmax"]], lat2 = bb[["ymax"]]
    )
  }

  # Empat kartu ringkasan (KPI) mengikuti indeks, wilayah, & rentang terpilih
  output$kpi_rata <- renderValueBox({
    d  <- data_zonal(); pr <- input$pilih_indeks
    v  <- d[[paste0(pr, "_Mean")]]; v <- v[is.finite(v)]
    if (length(v) == 0)
      return(valueBox("\u2014", paste("Rata-rata", meta_indeks[[pr]]$singkat),
                      icon = icon("chart-line"), color = "blue"))
    valueBox(sprintf("%.3f", mean(v)),
             paste("Rata-rata", meta_indeks[[pr]]$singkat),
             icon = icon("chart-line"), color = "blue")
  })

  output$kpi_tinggi <- renderValueBox({
    d  <- data_zonal(); pr <- input$pilih_indeks
    d  <- d[is.finite(d[[paste0(pr, "_Mean")]]), , drop = FALSE]
    if (nrow(d) == 0)
      return(valueBox("\u2014", paste("Tertinggi", meta_indeks[[pr]]$singkat),
                      icon = icon("arrow-up"), color = "green"))
    i <- which.max(d[[paste0(pr, "_Mean")]])
    valueBox(sprintf("%.3f", d[[paste0(pr, "_Mean")]][i]),
             paste("Tertinggi -", d$Kecamatan[i]),
             icon = icon("arrow-up"), color = "green")
  })

  output$kpi_rendah <- renderValueBox({
    d  <- data_zonal(); pr <- input$pilih_indeks
    d  <- d[is.finite(d[[paste0(pr, "_Mean")]]), , drop = FALSE]
    if (nrow(d) == 0)
      return(valueBox("\u2014", paste("Terendah", meta_indeks[[pr]]$singkat),
                      icon = icon("arrow-down"), color = "orange"))
    i <- which.min(d[[paste0(pr, "_Mean")]])
    valueBox(sprintf("%.3f", d[[paste0(pr, "_Mean")]][i]),
             paste("Terendah -", d$Kecamatan[i]),
             icon = icon("arrow-down"), color = "orange")
  })

  output$kpi_jumlah <- renderValueBox({
    d <- data_zonal()
    valueBox(nrow(d),
             paste("Kecamatan",
                   if (nrow(d) == nrow(zonal_rapi)) "dianalisis" else "terpilih"),
             icon = icon("map"), color = "purple")
  })

  # Grafik batang interaktif (plotly): urut dari nilai terendah ke tertinggi.
  # Hover menampilkan nilai; klik batang -> kecamatan disorot di peta &
  # baris tabelnya otomatis terpilih.
  output$grafik_zonal <- renderPlotly({
    d  <- data_zonal(); pr <- input$pilih_indeks
    d  <- d[is.finite(d[[paste0(pr, "_Mean")]]), , drop = FALSE]
    e  <- d[order(d[[paste0(pr, "_Mean")]]), , drop = FALSE]
    e$nilai     <- e[[paste0(pr, "_Mean")]]
    e$Kecamatan <- factor(e$Kecamatan, levels = e$Kecamatan)

    if (nrow(e) == 0) {
      return(plotly_empty(type = "bar") %>%
               layout(title = list(
                 text = "Tidak ada kecamatan pada rentang nilai ini",
                 font = list(size = 14, color = "#6b7686"))))
    }

    plot_ly(
      e,
      x = ~nilai, y = ~Kecamatan,
      type = "bar", orientation = "h",
      source = "zonal",
      customdata = ~Kecamatan,
      marker = list(color = palet_aksen[[pr]]),
      text = sprintf("%.3f", e$nilai),
      textposition = ifelse(e$nilai >= 0, "outside", "inside"),
      hovertemplate = "<b>%{y}</b><br>Rata-rata: %{x:.3f}<extra></extra>"
    ) %>%
      layout(
        title = list(text = meta_indeks[[pr]]$label,
                     font = list(size = 15, color = "#17233d")),
        xaxis = list(title = "Rata-rata", zeroline = TRUE,
                     zerolinecolor = "#dbe3f2", gridcolor = "#eef1f8"),
        yaxis = list(title = "", categoryorder = "array",
                     categoryarray = levels(e$Kecamatan)),
        margin = list(l = 96, r = 24, t = 42, b = 40),
        plot_bgcolor = "#ffffff",
        paper_bgcolor = "#ffffff",
        font = list(family = "Inter, Segoe UI, system-ui, sans-serif")
      ) %>%
      config(displayModeBar = FALSE) %>%
      event_register("plotly_click")
  })

  # Klik grafik -> sorot kecamatan di peta + pilih baris tabelnya
  # (baca input langsung agar tidak bergantung pada registrasi event_data)
  observeEvent(input[["plotly_click-zonal"]], {
    dat <- input[["plotly_click-zonal"]]
    if (is.null(dat)) return()
    # plotly mengirim event sebagai string JSON -> parse dulu
    if (is.character(dat)) {
      dat <- tryCatch(jsonlite::fromJSON(paste(dat, collapse = "")),
                      error = function(e) NULL)
      if (is.null(dat)) return()
    }
    # normalisasi ke satu record (bisa data.frame atau list)
    rec <- if (is.data.frame(dat)) {
      if (nrow(dat) == 0) return()
      as.list(dat[1, , drop = FALSE])
    } else if (is.list(dat) && length(dat) >= 1) {
      dat[[1]]
    } else {
      return()
    }
    kec <- as.character(rec$y)[1]
    if (is.na(kec) || !nzchar(kec)) kec <- as.character(rec$customdata)[1]
    if (is.na(kec) || !nzchar(kec)) return()
    sorot_kecamatan(kec)
    ti <- tabel_isi()
    i  <- match(kec, ti$Kecamatan)
    if (!is.na(i)) dataTableProxy("tabel_zonal") %>% selectRows(i)
  })

  # Klik baris tabel -> sorot kecamatan di peta
  observeEvent(input$tabel_zonal_rows_selected, {
    i <- input$tabel_zonal_rows_selected
    if (length(i) == 0) return()
    ti <- tabel_isi()
    if (i[1] <= nrow(ti)) sorot_kecamatan(ti$Kecamatan[i[1]])
  })

  # Data tabel rinci (lima kolom statistik untuk indeks yang dipilih)
  tabel_isi <- reactive({
    d  <- data_zonal(); pr <- input$pilih_indeks
    kol <- paste0(pr, "_", c("Mean", "Minimum", "Maximum", "Median", "SD"))
    data.frame(
      Kecamatan        = d$Kecamatan,
      Wilayah          = d$Wilayah,
      `Rata-rata`      = d[[kol[1]]],
      Minimum          = d[[kol[2]]],
      Maksimum         = d[[kol[3]]],
      Median           = d[[kol[4]]],
      `Simpangan Baku` = d[[kol[5]]],
      `Luas (ha)`      = round(d$Luas_ha, 1),
      check.names = FALSE,
      stringsAsFactors = FALSE
    )
  })

  # Tabel rinci: hanya lima kolom statistik untuk indeks yang dipilih
  output$tabel_zonal <- renderDT({
    tampil <- tabel_isi(); pr <- input$pilih_indeks
    hasil <- datatable(
      tampil,
      rownames   = FALSE,
      selection  = "single",
      extensions = "Buttons",
      caption    = htmltools::tags$caption(
        paste("Nilai", meta_indeks[[pr]]$label, "untuk", nrow(tampil), "kecamatan.")
      ),
      options = list(
        pageLength = 25,
        lengthMenu = c(10, 25, 50),
        dom        = "lBfrtip",
        order      = list(list(2, "desc")),
        columnDefs = list(list(className = "dt-center", targets = 1:7)),
        buttons    = list(
          list(extend = "csv",   text = "Unduh CSV"),
          list(extend = "excel", text = "Unduh Excel")
        )
      )
    ) %>%
      formatRound(columns = c("Rata-rata", "Minimum", "Maksimum", "Median",
                              "Simpangan Baku"), digits = 3)

    nilai    <- tampil$`Rata-rata`
    nilai_ok <- length(nilai) > 0 && any(is.finite(nilai))
    if (nilai_ok) {
      hasil <- hasil %>% formatStyle(
        "Rata-rata",
        background       = styleColorBar(range(nilai, na.rm = TRUE),
                                         palet_aksen[[pr]]),
        backgroundSize   = "100% 62%",
        backgroundRepeat = "no-repeat",
        backgroundPosition = "center"
      )
    }
    hasil
  })


  # -------------------------------------------------------------------------
  # 7.4 Modal "Tentang" - ringkasan proyek, sumber data, rumus, dan penulis
  # -------------------------------------------------------------------------
  observeEvent(input$btn_tentang, {

    rumus_indeks <- c(
      NDVI = "(B08 \u2212 B04) / (B08 + B04)",
      NDBI = "(B11 \u2212 B08) / (B11 + B08)",
      NDWI = "(B03 \u2212 B08) / (B03 + B08)",
      NDCI = "(B04 \u2212 B08) / (B04 + B08)"
    )

    showModal(modalDialog(
      title = tags$span("Tentang Aplikasi WebGIS Indeks Spektral"),
      easyClose = TRUE,
      footer     = modalButton("Tutup"),
      size       = "l",
      tags$div(
        style = "font-size:13.5px; line-height:1.65; color:#33405a;",

        tags$p(style = "margin-top:0;",
          "Dashboard WebGIS yang memvisualisasikan empat indeks spektral hasil ",
          "pemrosesan citra Sentinel-2 dan statistik zonal per kecamatan di ",
          "Kabupaten & Kota Madiun, sehingga karakteristik tutupan lahan tiap ",
          "wilayah bisa dibandingkan secara objektif."),

        tags$h4(style = "margin:16px 0 6px; color:#152340;", "Sumber data"),
        tags$ul(style = "margin:0; padding-left:19px;",
          tags$li("Citra ", tags$b("Sentinel-2 Level-2A"), " \u00b7 resolusi 10 m \u00b7 ",
                  "tanggal akuisisi 13 Juli 2026 \u00b7 tile T49MEM."),
          tags$li("Batas administrasi ", tags$b("18 kecamatan"),
                  " (15 Kabupaten Madiun dan 3 Kota Madiun).")
        ),

        tags$h4(style = "margin:14px 0 6px; color:#152340;", "Proses pengolahan"),
        tags$ul(style = "margin:0; padding-left:19px;",
          tags$li("Crop & mask citra mengikuti batas administrasi."),
          tags$li("Perhitungan empat indeks spektral dari band terkait."),
          tags$li("Reproject ke Web Mercator + agregasi agar ringan untuk web."),
          tags$li("Statistik zonal per kecamatan: mean, min, maks, median, dan simpangan baku.")
        ),

        tags$h4(style = "margin:14px 0 6px; color:#152340;", "Rumus indeks"),
        tags$table(
          style = "width:100%; border-collapse:collapse; font-size:13px;",
          tags$thead(tags$tr(
            lapply(c("Indeks", "Rumus", "Membaca"),
                   function(t) tags$th(t, style = paste("text-align:left; padding:6px 8px;",
                                                        "border-bottom:2px solid #dde5f3;",
                                                        "color:#33405a;")))
          )),
          tags$tbody(lapply(names(rumus_indeks), function(p) tags$tr(
            tags$td(tags$b(p), style = "padding:6px 8px; border-bottom:1px solid #eef1f8;"),
            tags$td(tags$code(rumus_indeks[[p]]),
                    style = "padding:6px 8px; border-bottom:1px solid #eef1f8; font-size:12.5px;"),
            tags$td(meta_indeks[[p]]$singkat,
                    style = "padding:6px 8px; border-bottom:1px solid #eef1f8;")
          )))
        ),
        tags$p(style = "color:#6b7686; font-size:12.5px; margin-top:8px;",
          "B03 = Green \u00b7 B04 = Red \u00b7 B08 = NIR \u00b7 B11 = SWIR (Sentinel-2)."),

        tags$h4(style = "margin:14px 0 6px; color:#152340;", "Pembuat & lisensi"),
        tags$p(style = "margin:0;",
          tags$b("Abul Fahmi Attaftazani"), " (NRP 5016241048) \u00b7 ",
          tags$b("Sabrina Sandra RA"), " (NRP 5016241061)"),
        tags$p(style = "margin:4px 0 0; color:#6b7686; font-size:12.5px;",
          "Dilisensikan di bawah MIT.")
      )
    ))
  })
}


# =============================================================================
# 8. JALANKAN APLIKASI
# =============================================================================

shinyApp(ui = ui, server = server)
