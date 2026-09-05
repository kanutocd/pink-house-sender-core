# frozen_string_literal: true

require "test_helper"

module Sender
  module Core
    class TestCapabilities < Minitest::Test
      def test_normalizes_and_deduplicates_capabilities
        capabilities = Capabilities.normalize(["email", :attachments, "email"])

        assert_equal %i[email attachments], capabilities
        assert_predicate capabilities, :frozen?
      end

      def test_rejects_invalid_capabilities
        assert_raises(ArgumentError) { Capabilities.normalize({}) }
        assert_raises(ArgumentError) { Capabilities.normalize([nil]) }
      end
    end
  end
end
