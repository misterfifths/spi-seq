# frozen_string_literal: true

# Returns an array representing a Euclidean rhythm that evenly spreads `pulses`
# hits over `length` many beats. The array contains booleans, true for hits and
# false for rests. If pulses is > 0, the first element of the result will always
# be true.
#
# If `rotate` is provided, the result is rotated leftward such that the first
# element is a hit, `rotate` many times.
#
# If `pulses` >= `length`, all values in the result will be true. If `pulses` is
# 0, all values will be false. It is an error to pass negative numbers for any
# argument, or non-integers.
#
# This is the analog to Sonic Pi's `spread` function, though note that it may
# not return hits in the exact order that Sonic Pi does.
def euclid(pulses, length, rotate: 0)
  raise TypeError, "all arguments must be integers" unless pulses.is_a?(Integer) && length.is_a?(Integer) && rotate.is_a?(Integer)
  raise RangeError, "all arguments must be >= 0" unless pulses >= 0 && length >= 0 && rotate >= 0

  # Rotation is meaningless in these cases
  return [] if length == 0
  return [true] * length if pulses >= length
  return [false] * length if pulses == 0

  res = []
  length.times do |i|
    # See the "Stateless One-Liners" section here:
    # https://paulbatchelor.github.io/sndkit/euclid/
    # Though note that we are using a different definition of rotation - we
    # rotate so the nth hit is in the first slot, like Sonic Pi.
    res << ((pulses * i) % length < pulses)
  end

  rotate += 1 unless res.first  # Always want a hit in the first slot
  # rubocop:disable Style/WhileUntilModifier
  while rotate > 0
    rotate -= 1 if res.rotate!.first
  end
  # rubocop:enable Style/WhileUntilModifier

  res
end
