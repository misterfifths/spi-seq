# `require` doesn't do what we want inside of spi, so we have to resort to eval.
# $SPI_EXTS_PATH must set externally before eval'ing this file.

eval File.read("#{$SPI_EXTS_PATH}/extapi.rb")

eval File.read("#{$SPI_EXTS_PATH}/midi-utils.rb")
eval File.read("#{$SPI_EXTS_PATH}/bezier.rb")
eval File.read("#{$SPI_EXTS_PATH}/easings.rb")  # Depends on bezier

eval File.read("#{$SPI_EXTS_PATH}/curves.rb")

# These are interdependent; order is important.
eval File.read("#{$SPI_EXTS_PATH}/noteutils.rb")
eval File.read("#{$SPI_EXTS_PATH}/arp.rb")
eval File.read("#{$SPI_EXTS_PATH}/notelength.rb")
eval File.read("#{$SPI_EXTS_PATH}/prob.rb")
eval File.read("#{$SPI_EXTS_PATH}/seq.rb")
eval File.read("#{$SPI_EXTS_PATH}/player.rb")
