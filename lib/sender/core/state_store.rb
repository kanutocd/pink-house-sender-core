# frozen_string_literal: true

module Sender
  module Core
    # Namespace for replaceable runtime state persistence implementations.
    module StateStore
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
