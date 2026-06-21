# frozen_string_literal: true

require_relative "../external/io"

module SpiSeq; module Internal; module Log
  # @private
  module State
    @silent = false
    class << self
      attr_accessor :silent
    end
  end

  module_function def silence!(flag = true)
    State.silent = flag
  end

  module_function def with_silence
    old_silent = State.silent
    State.silent = true
    yield
    State.silent = old_silent
  end

  module_function def log(msg, channel = "spi-seq")
    return if State.silent

    s = "[#{channel}] #{msg}"
    External::IO.puts(s)
  end

  module_function def warn(msg, channel = "spi-seq")
    log("warning: #{msg}", channel)
  end
end; end; end
