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
