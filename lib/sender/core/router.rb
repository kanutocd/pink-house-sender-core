# frozen_string_literal: true

module Sender
  module Core
    # Selects one eligible configured provider for a delivery.
    class Router
      # @param registry [ProviderRegistry] provider registry to route through
      def initialize(registry: ProviderRegistry.new, circuit_options: {}, state_store: StateStore::Memory.new,
                     observer: Observability::Memory.new)
        @registry = registry
        @circuit_options = circuit_options
        @state_store = state_store
        @observer = observer
        @election = Election.new(state_store: @state_store)
      end

      # Deliver a normalized message through the best eligible provider.
      #
      # Providers are ordered by descending priority, then by name for stable
      # tie-breaking. Failover is bounded by the eligible provider count.
      # @param message [Message] normalized outbound message
      # @param provider [Symbol, String, nil] optional explicit provider
      # @param max_attempts [Integer, nil] optional upper bound on attempts
      # @return [Delivery] provider-neutral delivery result
      def deliver(message, provider: nil, max_attempts: nil)
        validate_message(message)
        candidates = eligible_providers(provider, requirements: message.requirements)
        attempt_limit = validate_max_attempts(max_attempts || candidates.length)
        attempts = []
        last_error = nil

        candidates.first(attempt_limit).each do |candidate|
          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          delivery = candidate.deliver(message)
          previous_state = circuit_for(candidate).state
          record_circuit(candidate, &:record_success)
          current_state = circuit_for(candidate).state
          if previous_state != current_state
            emit(type: :circuit_transition, provider: candidate.name, from: previous_state,
                 to: current_state)
          end
          record_health(candidate) do |health|
            health.record_success(latency: elapsed_since(started_at), circuit_state: current_state)
          end
          emit(type: :attempt, provider: candidate.name, status: :accepted, latency: elapsed_since(started_at))
          return with_attempt(delivery, attempts, candidate.name, :accepted)
        rescue Errors::Base => e
          previous_state = circuit_for(candidate).state
          record_circuit(candidate) { |circuit| circuit.record_failure(e) }
          current_state = circuit_for(candidate).state
          if previous_state != current_state
            emit(type: :circuit_transition, provider: candidate.name, from: previous_state,
                 to: current_state)
          end
          record_health(candidate) do |health|
            health.record_failure(latency: elapsed_since(started_at), error: e, circuit_state: current_state)
          end
          emit(type: :attempt, provider: candidate.name, status: :failed, error: e.category,
               latency: elapsed_since(started_at))
          attempts << attempt_record(candidate.name, :failed, e)
          last_error = e
          if e.failover? && attempts.length < attempt_limit
            emit(type: :failover, from: candidate.name, to: candidates[attempts.length]&.name)
          end
          raise unless e.failover?
        end

        Delivery.new(status: :failed, provider: last_error.provider, attempts: attempts, error: last_error)
      end

      # @param name [Symbol, String] configured provider name
      # @return [Hash] current provider health snapshot
      def health(name)
        health_for(@registry.provider(name)).snapshot
      end

      # @return [Array<Hash>] structured events emitted by this router
      def events
        @observer.events
      end

      private

      def eligible_providers(name = nil, requirements: [])
        candidates = name ? [@registry.provider(name)] : @registry.providers
        selected = @election.rank(
          candidates, requirements: requirements, circuits: circuit_map(candidates), health: health_map(candidates)
        )
        persist_circuits(candidates)
        persist_health(candidates)
        emit(type: :election, candidates: selected.map(&:name), selected: selected.first&.name)
        return selected unless selected.empty?

        raise Errors::ConfigurationError.new("no eligible provider is configured", category: :configuration)
      end

      def validate_max_attempts(value)
        return value if value.is_a?(Integer) && value.positive?

        raise ArgumentError, "max_attempts must be a positive Integer"
      end

      def circuit_map(providers)
        providers.to_h { |provider| [provider.name, circuit_for(provider)] }
      end

      def health_map(providers)
        providers.to_h { |provider| [provider.name, health_for(provider)] }
      end

      def circuit_for(provider)
        value = @state_store.fetch([:circuit, provider.name]) { CircuitBreaker.new(**@circuit_options).to_h }
        value.is_a?(CircuitBreaker) ? value : CircuitBreaker.from_h(value, **@circuit_options)
      end

      def health_for(provider)
        value = @state_store.fetch([:health, provider.name]) { new_health.to_h }
        value.is_a?(Health) ? value : Health.from_h(value, observation_window: observation_window)
      end

      def observation_window
        @circuit_options.fetch(:observation_window, CircuitBreaker::DEFAULT_OBSERVATION_WINDOW)
      end

      def new_health
        Health.new(observation_window: observation_window)
      end

      def record_circuit(provider)
        @state_store.update([:circuit, provider.name], default: CircuitBreaker.new(**@circuit_options).to_h) do |value|
          circuit = value.is_a?(CircuitBreaker) ? value : CircuitBreaker.from_h(value, **@circuit_options)
          yield circuit
          circuit.to_h
        end
      end

      def record_health(provider)
        @state_store.update([:health, provider.name], default: new_health.to_h) do |value|
          health = value.is_a?(Health) ? value : Health.from_h(value, observation_window: observation_window)
          yield health
          health.to_h
        end
      end

      def persist_circuits(providers)
        providers.each { |provider| @state_store.write([:circuit, provider.name], circuit_for(provider).to_h) }
      end

      def persist_health(providers)
        providers.each { |provider| @state_store.write([:health, provider.name], health_for(provider).to_h) }
      end

      def elapsed_since(started_at)
        Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
      end

      def emit(event)
        @observer.emit(event)
      end

      def attempt_record(provider, status, error = nil)
        { provider: provider, status: status, error: error&.category }.compact
      end

      def with_attempt(delivery, attempts, provider, status)
        Delivery.new(
          status: delivery.status,
          provider: delivery.provider,
          provider_message_id: delivery.provider_message_id,
          attempts: attempts + [attempt_record(provider, status)],
          error: delivery.error,
          metadata: delivery.metadata
        )
      end

      def validate_message(message)
        return if message.is_a?(Message)

        raise ArgumentError, "message must be a Sender::Core::Message"
      end
    end
  end
end
