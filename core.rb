# `require` doesn't do what we want inside of spi, so we have to resort to eval.
# $SPI_EXTS_PATH must set externally before eval'ing this file.

eval File.read("#{$SPI_EXTS_PATH}/midi-utils.rb")
eval File.read("#{$SPI_EXTS_PATH}/seq.rb")  # this depends on midi-utils
eval File.read("#{$SPI_EXTS_PATH}/bezier.rb")
eval File.read("#{$SPI_EXTS_PATH}/easings.rb")  # this depends on bezier
