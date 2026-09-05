# frozen_string_literal: true

module Sender
  module Core
    # Immutable configuration shared by provider adapters.
    class ProviderConfiguration
      # Advisory integration maturity values exposed by provider registries.
      SUPPORT_LEVELS = %i[unknown experimental supported fully_tested deprecated unsupported].freeze

      attr_reader :name, :settings, :enabled, :priority, :capabilities, :support_level

      # @param name [Symbol, String] provider name
      # @param settings [Hash] provider-specific settings
      # @param enabled [Boolean] whether the provider may be used
      # @param priority [Integer] static provider preference
      # @param capabilities [Array<Symbol>] advertised capabilities
      def initialize(name:, settings: {}, enabled: true, priority: 0, capabilities: [])
        @name = normalize_name(name)
        @settings = normalize_settings(settings)
        @enabled = validate_enabled(enabled)
        @priority = validate_priority(priority)
        @capabilities = normalize_capabilities(capabilities)
        @support_level = :unknown
        freeze
      end

      # Return a copy with advisory integration metadata attached.
      # @param value [Symbol] advisory integration maturity metadata
      # @return [ProviderConfiguration] copied configuration
      def with_support_level(value)
        copy = dup
        copy.instance_variable_set(:@support_level, validate_support_level(value))
        copy.freeze
      end

      # @param key [Symbol, String] setting name
      # @return [Object, nil] configured setting
      def [](key)
        settings[key] || settings[key.to_sym]
      end

      # @return [Boolean] whether this configuration has been enabled
      def enabled?
        enabled
      end

      private

      def normalize_name(value)
        name = value.to_sym
        raise ArgumentError, "name must not be empty" if name.empty?

        name
      rescue NoMethodError
        raise ArgumentError, "name must be symbolizable"
      end

      def normalize_settings(value)
        raise ArgumentError, "settings must be a Hash" unless value.is_a?(Hash)

        value.dup.freeze
      end

      def validate_enabled(value)
        return value if [true, false].include?(value)

        raise ArgumentError, "enabled must be true or false"
      end

      def validate_priority(value)
        return value if value.is_a?(Integer)

        raise ArgumentError, "priority must be an Integer"
      end

      def normalize_capabilities(value)
        Capabilities.normalize(value)
      end

      def validate_support_level(value)
        level = value.to_sym
        return level if SUPPORT_LEVELS.include?(level)

        raise ArgumentError, "support_level must be one of: #{SUPPORT_LEVELS.join(", ")}"
      rescue NoMethodError
        raise ArgumentError, "support_level must be symbolizable"
      end
    end
  end
end
