#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "test_helper"
require_relative "../extapi"

class ExtApiTest < Test::Unit::TestCase
  def test_rand
    assert_instance_of Float, ExtApi.rand
    assert_instance_of Float, ExtApi.rand(5)
    assert_instance_of Float, ExtApi.rand(1..5)

    # These are obviously not exhaustive; just trying to catch anything glaring.
    assert ExtApi.rand < 1
    assert ExtApi.rand >= 0
    assert ExtApi.rand(5) < 5
    assert ExtApi.rand(5) > 0
    assert ExtApi.rand(1...5) >= 1
    assert ExtApi.rand(1...5) < 5
    assert ExtApi.rand(1..5) <= 6
  end

  def test_rand_i
    assert_instance_of Integer, ExtApi.rand_i
    assert_instance_of Integer, ExtApi.rand_i(5)
    assert_instance_of Integer, ExtApi.rand_i(1..3)
    assert_instance_of Integer, ExtApi.rand_i(0)

    # Again, these are kind of silly, just looking for glaring issues.
    assert ExtApi.rand_i >= 0
    assert ExtApi.rand_i <= 1
    assert ExtApi.rand_i(5) >= 0
    assert ExtApi.rand_i(5) < 5
    assert ExtApi.rand_i(1..3) >= 1
    assert ExtApi.rand_i(1...3) < 3
    assert ExtApi.rand_i(1..3) <= 3
  end

  def test_choose
    assert_includes [1, 2, 3], ExtApi.choose([1, 2, 3])
    assert_equal 1, ExtApi.choose([1])

    callable = ExtApi.choose
    assert_includes [1, 2, 3], callable[[1, 2, 3]]
    assert_equal 1, callable[[1]]
  end

  def test_one_in
    assert_equal false, ExtApi.one_in(0)

    1.upto(10) do |n|
      avg = 0
      10000.times { avg += ExtApi.one_in(n) ? 1 : 0 }
      avg /= 10000.0
      assert_in_delta avg, 1 / n.to_f, 0.02
    end
  end

  def test_get_set
    assert_nil ExtApi.get(:key)

    ExtApi.set(:key, 123)
    assert_equal ExtApi.get(:key), 123
    ExtApi.set(:key, "abc")
    assert_equal ExtApi.get(:key), "abc"

    callable = ExtApi.get
    assert_equal callable[:key], "abc"

    ExtApi.set(:key, nil)
    assert_nil ExtApi.get(:key)
    assert_nil callable[:key]
  end
end
