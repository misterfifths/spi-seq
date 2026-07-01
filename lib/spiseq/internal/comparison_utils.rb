# frozen_string_literal: true

module SpiSeq; module Internal; module ComparisonUtils
  # Prepends a module defining comparison operators on that delegate to the RHS
  # of the operation if the RHS is of type `cls`. Useful on builtin classes like
  # String and Symbol to allow "yoda" comparisons with another class.
  module_function def monkey_patch_reverse_comparisons(target, cls)
    patch_module = Module.new do
      {
        :eql? => :eql?,
        :==   => :==,
        :<    => :>,
        :<=   => :>=,
        :>    => :<,
        :>=   => :<=
      }.each do |op, inverse_op|
        define_method(op) do |other|
          next other.send(inverse_op, self) if other.instance_of?(cls)
          super(other)
        end
      end

      define_method(:<=>) do |other|
        if other.instance_of?(cls)
          res = other <=> self
          next res if res.nil?
          -res
        else
          super(other)
        end
      end
    end

    target.prepend(patch_module)
  end
end; end; end
