# frozen_string_literal: true

require "test_helper"
require "support/state_store_contract"

module Sender
  module Core
    module StateStore
      class TestMemory < Minitest::Test
        include StateStoreContract

        private

        def build_state_store
          Memory.new
        end

        public

        def test_reads_writes_fetches_and_deletes_values
          store = Memory.new

          assert_nil store.read(:missing)
          assert_equal "value", store.write(:key, "value")
          assert_equal "value", store.read(:key)
          assert_equal "value", store.fetch(:key) { raise "not called" }
          created = Object.new

          assert_same created, store.fetch(:created) { created }
          assert_equal "value", store.delete(:key)
          assert_nil store.read(:key)
        end

        def test_clear_removes_all_values
          store = Memory.new
          store.write(:one, 1)
          store.write(:two, 2)

          assert_empty store.clear
          assert_nil store.read(:one)
          assert_nil store.read(:two)
        end

        def test_fetch_initializes_shared_state_once_under_concurrency
          store = Memory.new
          values = []
          threads = 10.times.map do
            Thread.new { values << store.fetch(:shared) { Object.new } }
          end
          threads.each(&:join)

          assert_equal 1, values.map(&:object_id).uniq.length
        end

        def test_updates_values_atomically
          store = Memory.new
          threads = 10.times.map do
            Thread.new { 100.times { store.update(:count, default: 0) { |value| value + 1 } } }
          end
          threads.each(&:join)

          assert_equal 1_000, store.read(:count)
        end

        def test_validates_the_state_store_contract
          store = Memory.new

          assert_same store, Contract.validate!(store)
          error = assert_raises(ArgumentError) { Contract.validate!(Object.new) }

          assert_includes error.message, "read"
          assert_includes error.message, "update"
        end
      end

      class TestRedis < Minitest::Test
        include StateStoreContract

        class FakeRedis
          attr_reader :values

          def initialize(conflicts: 0)
            @values = {}
            @conflicts = conflicts
            @transaction_key = nil
            @transaction = nil
          end

          def call(command, *arguments)
            case command
            when "GET" then @values[arguments.first]
            when "SET" then set(arguments)
            when "DEL" then arguments.each { |key| @values.delete(key) }.length
            when "SCAN" then ["0", @values.keys.select { |key| key.start_with?(arguments[2].delete_suffix("*")) }]
            when "WATCH" then @transaction_key = arguments.first
            when "MULTI" then @transaction = true
            when "EXEC"
              return nil if @conflicts.positive? && (@conflicts -= 1) >= 0

              @transaction = false
              []
            when "UNWATCH" then @transaction_key = nil
            end
          end

          private

          def set(arguments)
            @values[arguments[0]] = arguments[1]
            "OK"
          end
        end

        def test_serializes_and_namespaces_values
          redis = FakeRedis.new
          store = Redis.new(redis: redis, namespace: "app", ttl: 60)

          assert_equal({ count: 1 }, store.write(:health, { count: 1 }))
          assert_equal({ "count" => 1 }, store.read(:health))
          assert_equal ["app:health"], redis.values.keys
        end

        def test_updates_and_deletes_values
          store = Redis.new(redis: FakeRedis.new)

          assert_equal 2, store.update(:count, default: 1) { |value| value + 1 }
          assert_equal 2, store.delete(:count)
          assert_nil store.read(:count)
        end

        def test_retries_an_optimistic_transaction_conflict
          store = Redis.new(redis: FakeRedis.new(conflicts: 1))

          assert_equal 3, store.update(:count, default: 1) { |value| value + 1 }
        end

        def test_clears_only_its_namespace
          redis = FakeRedis.new
          store = Redis.new(redis: redis, namespace: "app")
          store.write(:one, 1)
          Redis.new(redis: redis, namespace: "other").write(:two, 2)

          assert_nil store.clear
          assert_nil store.read(:one)
          assert_equal 2, Redis.new(redis: redis, namespace: "other").read(:two)
        end

        def test_rejects_malformed_redis_state
          redis = FakeRedis.new
          redis.values["sender-core:broken"] = "not-json"

          assert_raises(Error) { Redis.new(redis: redis).read(:broken) }
        end

        def test_validates_redis_configuration
          assert_raises(ArgumentError) { Redis.new(redis: FakeRedis.new, namespace: "") }
          assert_raises(ArgumentError) { Redis.new(redis: FakeRedis.new, ttl: 0) }
          assert_raises(ArgumentError) { Redis.new(redis: FakeRedis.new, max_retries: 0) }
        end

        private

        def build_state_store
          Redis.new(redis: FakeRedis.new)
        end
      end
    end
  end
end
