# frozen_string_literal: true

module Sender
  module Core
    # Namespace for replaceable runtime state persistence implementations.
    module StateStore
      require "json"

      # Contract shared by in-memory, Redis, and custom state-store backends.
      module Contract
        # Methods required from a state-store backend.
        REQUIRED_METHODS = %i[read write fetch update delete clear].freeze
        # State keys must be deterministic and safe to serialize by a backend.
        KEY_REQUIREMENTS = "non-nil, deterministic, and backend-serializable"

        # Validate that an object exposes the state-store contract.
        # @param store [Object] candidate state-store backend
        # @return [Object] the validated backend
        def self.validate!(store)
          missing = REQUIRED_METHODS.reject { |method| store.respond_to?(method) }
          return store if missing.empty?

          raise ArgumentError, "state store is missing methods: #{missing.join(", ")}"
        end

        # Validate a state key before handing it to a backend.
        # @param key [Object] candidate state key
        # @return [Object] the validated key
        def self.validate_key!(key)
          return key unless key.nil?

          raise ArgumentError, "state store keys must not be nil"
        end
      end

      # Redis-backed state store for process-shared primitive state.
      class Redis
        # @param redis [#call] Redis client exposing command calls
        # @param namespace [String] key namespace shared by this store
        # @param ttl [Integer, nil] optional key lifetime in seconds
        # @param max_retries [Integer] optimistic transaction retries
        def initialize(redis:, namespace: "sender-core", ttl: nil, max_retries: 3)
          @redis = redis
          @namespace = validate_namespace(namespace)
          @ttl = validate_ttl(ttl)
          @max_retries = validate_retries(max_retries)
        end

        # @return [Object, nil] decoded value
        def read(key)
          decode(@redis.call("GET", redis_key(key)))
        end

        # @return [Object] stored value
        def write(key, value)
          command = ["SET", redis_key(key), encode(value)]
          command.push("EX", @ttl) if @ttl
          @redis.call(*command)
          value
        end

        # @return [Object] existing or initialized value
        def fetch(key, &)
          value = read(key)
          return value unless value.nil?

          update(key, default: nil, &)
        end

        # Atomically transform a value using Redis optimistic transactions.
        # @return [Object] stored transformed value
        def update(key, default: nil)
          redis_key = redis_key(key)
          attempts = 0
          loop do
            attempts += 1
            @redis.call("WATCH", redis_key)
            current = decode(@redis.call("GET", redis_key))
            value = yield(current.nil? ? default : current)
            @redis.call("MULTI")
            command = ["SET", redis_key, encode(value)]
            command.push("EX", @ttl) if @ttl
            @redis.call(*command)
            return value unless @redis.call("EXEC").nil?
            raise Error, "Redis state update exceeded retry limit" if attempts >= @max_retries
          rescue StandardError
            @redis.call("UNWATCH")
            raise
          end
        end

        # @return [Object, nil] deleted value
        def delete(key)
          value = read(key)
          @redis.call("DEL", redis_key(key))
          value
        end

        # Delete all keys in this store namespace.
        def clear
          cursor = "0"
          loop do
            cursor, keys = @redis.call("SCAN", cursor, "MATCH", "#{@namespace}:*")
            @redis.call("DEL", *keys) unless keys.empty?
            break if cursor.to_s == "0"
          end
          nil
        end

        private

        def redis_key(key)
          Contract.validate_key!(key)
          "#{@namespace}:#{canonical_key(key)}"
        end

        def canonical_key(key)
          values = key.is_a?(Array) ? key : [key]
          values.join(":")
        end

        def encode(value)
          JSON.generate(value)
        rescue JSON::GeneratorError => e
          raise ArgumentError, "state value must be JSON-serializable: #{e.message}"
        end

        def decode(value)
          return if value.nil?

          JSON.parse(value)
        rescue JSON::ParserError => e
          raise Error, "Redis state contains invalid JSON: #{e.message}"
        end

        def validate_namespace(value)
          raise ArgumentError, "namespace must be a non-empty String" unless value.is_a?(String) && !value.empty?

          value
        end

        def validate_ttl(value)
          return unless value
          return value if value.is_a?(Integer) && value.positive?

          raise ArgumentError, "ttl must be a positive Integer"
        end

        def validate_retries(value)
          return value if value.is_a?(Integer) && value.positive?

          raise ArgumentError, "max_retries must be a positive Integer"
        end
      end

      # Thread-safe process-local state store.
      class Memory
        def initialize
          @values = {}
          @lock = Mutex.new
        end

        # @param key [Object] state key
        # @return [Object, nil] stored value
        def read(key)
          @lock.synchronize { @values[Contract.validate_key!(key)] }
        end

        # Store a value and return it.
        # @param key [Object] state key
        # @param value [Object] state value
        # @return [Object] stored value
        def write(key, value)
          @lock.synchronize { @values[Contract.validate_key!(key)] = value }
        end

        # Read a value or initialize it atomically.
        # @param key [Object] state key
        # @return [Object] existing or initialized value
        def fetch(key)
          @lock.synchronize do
            normalized_key = Contract.validate_key!(key)
            @values.fetch(normalized_key) { @values[normalized_key] = yield }
          end
        end

        # Atomically transform a value, initializing it when absent.
        # The block must not re-enter this store while it is executing.
        # @param key [Object] state key
        # @param default [Object, nil] value supplied when the key is absent
        # @return [Object] stored transformed value
        def update(key, default: nil)
          @lock.synchronize do
            normalized_key = Contract.validate_key!(key)
            @values[normalized_key] = yield(@values.fetch(normalized_key, default))
          end
        end

        # Remove a value.
        # @param key [Object] state key
        # @return [Object, nil] removed value
        def delete(key)
          @lock.synchronize { @values.delete(Contract.validate_key!(key)) }
        end

        # Remove all state values.
        def clear
          @lock.synchronize { @values.clear }
        end
      end
    end
  end
end
