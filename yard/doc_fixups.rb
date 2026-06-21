# frozen_string_literal: true

# Hide a few things from yard. Easier to do this all at once than to scatter it
# across the implementation files.
#-
module SpiSeq
  # @private
  module Internal; end

  # @private
  module External; end
end
