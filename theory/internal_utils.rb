# frozen_string_literal: true

# @private
module SpiSeq
  module Utils
    # Defines comparison operators on `ctx` that delegate to the RHS of the
    # operation if the RHS is of type `cls`. Intended to be called at the class
    # level (with ctx = self) on, e.g., Symbol and String, to allow comparisons
    # with such types on the LHS.
    def self.define_reverse_comparison_ops(ctx, cls)
      {
        :eql? => :eql?,
        :==   => :==,
        :<    => :>,
        :<=   => :>=,
        :>    => :<,
        :>=   => :<=
      }.each do |op, inverse_op|
        ctx.define_method(op) do |other|
          next other.send(inverse_op, self) if other.instance_of?(cls)
          super(other)
        end
      end

      ctx.define_method(:<=>) do |other|
        next -(other <=> self) if other.instance_of?(cls)
        super(other)
      end
    end
  end
end
