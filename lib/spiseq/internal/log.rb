# frozen_string_literal: true

require_relative "../external/io"

module SpiSeq; module Internal; module Log
  # @private
  module State
    @quiet = false
    class << self
      attr_accessor :quiet
    end
  end

  module_function def quiet!(flag = true)
    State.quiet = flag
  end

  module_function def with_quiet
    old_quiet = State.quiet
    State.quiet = true
    yield
    State.quiet = old_quiet
  end

  module_function def log(msg, channel = "spi-seq", ignore_quiet: false)
    return if State.quiet && !ignore_quiet

    s = "[#{channel}] #{msg}"
    External::IO.puts(s)
  end

  module_function def warn(msg, channel = "spi-seq")
    log("warning: #{msg}", channel)
  end

  module_function def err(msg, channel = "spi-seq")
    log("error: #{msg}", channel, ignore_quiet: true)
  end
end; end; end
