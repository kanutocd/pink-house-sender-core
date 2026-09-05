# frozen_string_literal: true

module Sender
  module Core
    # Thread-safe in-memory health history for one provider.
    class Health
      # @param observation_window [Numeric] period for retaining observations
      # @param clock [#call] monotonic clock returning seconds
      def initialize(observation_window: CircuitBreaker::DEFAULT_OBSERVATION_WINDOW,
                     clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
        unless observation_window.is_a?(Numeric) && observation_window.positive?
          raise ArgumentError, "observation_window must be a positive number"
        end

        @observation_window = observation_window
        @clock = clock
        @successes = []
        @failures = []
        @consecutive_failures = 0
        @circuit_state = :closed
        @lock = Mutex.new
      end

      # Record a successful provider attempt.
      # @param latency [Numeric] elapsed request time in seconds
      # @param circuit_state [Symbol] circuit state after the attempt
      def record_success(latency:, circuit_state: :closed)
        @lock.synchronize do
          prune
          @successes << [@clock.call, validate_latency(latency)]
          @consecutive_failures = 0
          @circuit_state = circuit_state.to_sym
        end
      end

      # Record a failed provider attempt.
      # @param latency [Numeric] elapsed request time in seconds
      # @param error [Errors::Base] normalized error
      # @param circuit_state [Symbol] circuit state after the attempt
      def record_failure(latency:, error:, circuit_state: :closed)
        @lock.synchronize do
          prune
          @failures << [@clock.call, validate_latency(latency), error.category]
          @consecutive_failures += 1
          @circuit_state = circuit_state.to_sym
        end
      end

      # @return [Hash] immutable health snapshot
      def snapshot
        @lock.synchronize do
          prune
          latencies = (@successes + @failures).map { |event| event[1] }
          snapshot_values(latencies).freeze
        end
      end

      # Return the mutable observation history in a JSON-serializable form.
      # @return [Hash] health state snapshot
      def to_h
        @lock.synchronize do
          {
            successes: @successes,
            failures: @failures,
            consecutive_failures: @consecutive_failures,
            circuit_state: @circuit_state
          }
        end
      end

      # Rehydrate health history from a state-store snapshot.
      # @param value [Hash] serialized health state
      # @return [Health] reconstructed health record
      def self.from_h(value, observation_window: CircuitBreaker::DEFAULT_OBSERVATION_WINDOW)
        health = new(observation_window: observation_window)
        health.send(:load_state, value)
        health
      end

      private

      def load_state(value)
        raise ArgumentError, "health state must be a Hash" unless value.is_a?(Hash)

        @successes = value.fetch(:successes, value.fetch("successes", [])).map { |event| event.map(&:to_f) }
        @failures = value.fetch(:failures, value.fetch("failures", [])).map do |event|
          [event[0].to_f, event[1].to_f, event[2].to_sym]
        end
        @consecutive_failures = value[:consecutive_failures] || value["consecutive_failures"] || 0
        @circuit_state = (value[:circuit_state] || value["circuit_state"] || :closed).to_sym
      end

      def prune
        cutoff = @clock.call - @observation_window
        @successes.reject! { |event| event[0] < cutoff }
        @failures.reject! { |event| event[0] < cutoff }
        @consecutive_failures = 0 if @failures.empty?
      end

      def snapshot_values(latencies)
        {
          recent_successes: @successes.length,
          recent_failures: @failures.length,
          consecutive_failures: @consecutive_failures,
          average_latency: latencies.empty? ? nil : latencies.sum / latencies.length.to_f,
          circuit_state: @circuit_state
        }
      end

      def validate_latency(value)
        return value if value.is_a?(Numeric) && value >= 0

        raise ArgumentError, "latency must be a non-negative number"
      end
    end
  end
end
