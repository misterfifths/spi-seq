# frozen_string_literal: true

require_relative "extapi"

# Runs the given block the first time the script runs, and whenever it is
# restarted after having been stopped. thread_name is the name used for the
# internal thread this relies on. If you need independent cold-run blocks, you
# should provide different names for each call to this function.
def on_cold_run(thread_name = :__default_cold_run, &block)
  ExtApi.in_thread(name: thread_name) do
    block.call

    # spin to keep this thread alive until the script is manually stopped
    loop { ExtApi.sleep(100) }
  end
end

# Executes its block exactly once per run of Sonic Pi. The key argument, if
# provided, disambiguates different blocks; if you need independent one-time
# initializers, you should provide different keys for each call to this
# function.
def one_time_init(key = :default)
  # rubocop:disable Style/GlobalVars
  $__ONE_TIME_INIT_KEYS ||= Set.new
  unless $__ONE_TIME_INIT_KEYS.include?(key)
    yield
    $__ONE_TIME_INIT_KEYS.add(key)
  end
  # rubocop:enable Style/GlobalVars
end
