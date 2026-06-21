# frozen_string_literal: true

require_relative "utils"

module SpiSeq; module Internal; module Clipboard
  # Copies the given string to the clipboard. Only supported on macOS.
  module_function def copy(s)
    unless Utils.is_macos?
      Log.warn("clipboard functionality is only available on macOS")
      return
    end

    IO.popen("/usr/bin/pbcopy", "w") do |pipe|
      pipe.print(s)
      pipe.close_write
    end
  end

  # Returns the contents of the clipboard as a string. Only supported on macOS.
  module_function def paste
    unless Utils.is_macos?
      Log.warn("clipboard functionality is only available on macOS")
      return
    end

    IO.popen("/usr/bin/pbpaste", "r") do |pipe|
      return pipe.read
    end
  end
end; end; end
