# frozen_string_literal: true

require "test_helper"

module Sender
  module Core
    class TestErrors < Minitest::Test
      def test_failover_errors_are_retryable
        %i[network timeout rate_limited provider_unavailable].each do |category|
          error = Errors.const_get(category_class_name(category)).new(category: category, provider: :provider)

          assert_predicate error, :retryable?
          assert_predicate error, :failover?
        end
      end

      def test_authentication_errors_are_retryable_but_not_failover_eligible
        %i[authentication authorization].each do |category|
          error = Errors.const_get(category_class_name(category)).new(category: category)

          assert_predicate error, :retryable?
          refute_predicate error, :failover?
        end
      end

      def test_terminal_errors_are_not_retryable
        %i[invalid_request invalid_recipient provider_rejected unknown].each do |category|
          error = Errors.const_get(category_class_name(category)).new(category: category)

          refute_predicate error, :retryable?
          refute_predicate error, :failover?
        end
      end

      def test_error_preserves_provider_and_infers_category
        error = Errors::Timeout.new(provider: :provider)
        anonymous_error = Class.new(Errors::Base).new

        assert_equal :timeout, error.category
        assert_equal :provider, error.provider
        assert_equal :unknown, anonymous_error.category
      end

      private

      def category_class_name(category)
        category.to_s.split("_").map(&:capitalize).join
      end
    end
  end
end
