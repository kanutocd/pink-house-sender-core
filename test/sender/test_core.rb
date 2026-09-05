# frozen_string_literal: true

require "test_helper"

module Sender
  class TestCore < Minitest::Test
    def test_that_it_has_a_version_number
      refute_nil ::Sender::Core::VERSION
    end

    def test_error_is_a_standard_error
      assert_operator Sender::Core::Error, :<, StandardError
    end
  end
end
