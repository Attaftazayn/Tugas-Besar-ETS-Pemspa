# Jalankan seluruh pengujian testthat di proyek ini.
#
#   Dari akar proyek : Rscript tests/testthat.R
#   Atau di RStudio  : testthat::test_dir("tests/testthat")

library(testthat)

# Akar proyek bergantung pada direktori kerja saat skrip dijalankan
akar <- if (file.exists("utils.R")) "." else if (file.exists("../utils.R")) ".." else "../.."
source(file.path(akar, "utils.R"))

res <- test_dir(file.path(akar, "tests", "testthat"))
print(res)
