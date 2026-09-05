# frozen_string_literal: true

require "test_helper"

module Sender
  module Core
    class TestMessage < Minitest::Test
      def test_normalizes_and_freezes_a_message
        message = Message.new(
          to: "  recipient@example.test  ",
          body: "Hello",
          metadata: { request_id: "abc" },
          requirements: ["email", :attachments, "email"]
        )

        assert_equal "recipient@example.test", message.to
        assert_equal "Hello", message.body
        assert_equal({ request_id: "abc" }, message.metadata)
        assert_equal %i[email attachments], message.requirements
        assert_predicate message, :frozen?
      end

      def test_rejects_invalid_values
        assert_raises(ArgumentError) { Message.new(to: nil, body: "body") }
        assert_raises(ArgumentError) { Message.new(to: " ", body: "body") }
        assert_raises(ArgumentError) { Message.new(to: "to", body: nil) }
        assert_raises(ArgumentError) { Message.new(to: "to", body: " ") }
        assert_raises(ArgumentError) { Message.new(to: "to", body: "body", metadata: []) }
        assert_raises(ArgumentError) { Message.new(to: "to", body: "body", requirements: {}) }
      end
    end
  end
end
