# `require` doesn't do what we want inside of spi, so we have to resort to eval.
# $SPI_EXTS_PATH must set externally before eval'ing this file.

eval IO.read("#{$SPI_EXTS_PATH}/midi-utils.rb")
eval IO.read("#{$SPI_EXTS_PATH}/piano-roll2.rb")  # this depends on midi-utils
eval IO.read("#{$SPI_EXTS_PATH}/bezier.rb")
eval IO.read("#{$SPI_EXTS_PATH}/easings.rb")  # this depends on bezier
