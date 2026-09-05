# frozen_string_literal: true

require "test_helper"

module Sender
  module Core
    module StateStore
      class TestRedisIntegration < Minitest::Test
        def setup
          skip "set SENDER_CORE_REDIS_URL to run Redis integration tests" unless ENV["SENDER_CORE_REDIS_URL"]

          require "redis_client"
          @redis = RedisClient.config(url: ENV.fetch("SENDER_CORE_REDIS_URL")).new_client
          @store_namespace = "sender-core-test-#{Process.pid}-#{object_id}"
          @store = Redis.new(redis: @redis, namespace: @store_namespace, ttl: 60, max_retries: 100)
        rescue LoadError
          skip "redis-client is not installed"
        end

        def teardown
          @store&.clear
          @redis&.close
        end

        def test_round_trips_snapshots_and_updates_concurrently
          circuit, health = write_snapshots
          update_concurrently

          assert_equal circuit.to_h, CircuitBreaker.from_h(@store.read(:circuit)).to_h
          assert_equal health.to_h, Health.from_h(@store.read(:health)).to_h
          assert_equal 100, @store.read(:count)
        end

        private

        def write_snapshots
          circuit = CircuitBreaker.new
          health = Health.new
          health.record_success(latency: 0.25)
          @store.write(:circuit, circuit.to_h)
          @store.write(:health, health.to_h)
          [circuit, health]
        end

        def update_concurrently
          workers = 4.times.map { Thread.new { increment_count } }
          workers.each(&:join)
        end

        def increment_count
          client = RedisClient.config(url: ENV.fetch("SENDER_CORE_REDIS_URL")).new_client
          store = Redis.new(redis: client, namespace: @store_namespace, ttl: 60, max_retries: 100)
          25.times { store.update(:count, default: 0) { |value| value + 1 } }
        ensure
          client&.close
        end
      end
    end
  end
end
