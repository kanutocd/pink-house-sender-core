# frozen_string_literal: true

module Sender
  module Core
    # Catalogs, configures, and lazily loads provider adapters.
    class ProviderRegistry
      # Internal metadata for a registered provider.
      Entry = Struct.new(:name, :loader, :capabilities, :support_level, keyword_init: true) do
        def load
          adapter = loader.call
          raise Errors::ConfigurationError, "provider #{name} loader did not return a class" unless adapter.is_a?(Class)

          adapter
        end
      end

      # Empty by default; channel gems register their provider adapters.
      DEFAULT_PROVIDERS = {}.freeze

      # @param catalog [Hash] provider names mapped to adapter paths or metadata
      # @param default_capabilities [Array<Symbol>] catalog entry capabilities
      def initialize(catalog: DEFAULT_PROVIDERS, default_capabilities: [])
        @entries = {}
        @configurations = {}
        catalog.each do |name, definition|
          path, support_level = catalog_definition(definition)
          register(name, loader: lazy_loader(path), capabilities: default_capabilities, support_level:)
        end
      end

      # @return [Array<Symbol>] providers known to the registry
      def supported
        @entries.keys.freeze
      end

      # @return [Array<Symbol>] configured providers
      def configured
        @configurations.keys.freeze
      end

      # @return [Hash] advisory metadata for a registered provider
      def provider_metadata(name)
        entry = fetch_entry(name)
        {
          name: entry.name,
          capabilities: entry.capabilities,
          support_level: entry.support_level
        }.freeze
      end

      # Register a provider without loading its adapter.
      # @param name [Symbol, String] provider name
      # @param loader [#call] callable returning the adapter class
      # @param capabilities [Array<Symbol>] advertised capabilities
      # @param support_level [Symbol] advisory integration maturity metadata
      def register(name, loader:, capabilities: [:sms], support_level: :unknown)
        provider_name = normalize_name(name)
        raise ArgumentError, "loader must respond to call" unless loader.respond_to?(:call)
        raise ArgumentError, "provider already registered: #{provider_name}" if @entries.key?(provider_name)

        @entries[provider_name] = Entry.new(
          name: provider_name,
          loader: loader,
          capabilities: Capabilities.normalize(capabilities),
          support_level: normalize_support_level(support_level)
        ).freeze
        provider_name
      end

      # Configure a registered provider without loading its adapter.
      # @return [ProviderConfiguration] the stored configuration
      def configure(name, settings: {}, enabled: true, priority: 0, capabilities: nil)
        entry = fetch_entry(name)
        configuration = ProviderConfiguration.new(
          name: entry.name,
          settings: settings,
          enabled: enabled,
          priority: priority,
          capabilities: capabilities || entry.capabilities
        ).with_support_level(entry.support_level)
        @configurations[entry.name] = configuration
      end

      # Instantiate a configured provider, loading its adapter on demand.
      # @return [Provider] configured provider adapter
      def provider(name)
        entry = fetch_entry(name)
        configuration = @configurations.fetch(entry.name) do
          raise Errors::ConfigurationError, "provider is not configured: #{entry.name}"
        end
        entry.load.new(configuration: configuration)
      rescue LoadError => e
        raise Errors::ConfigurationError, "could not load provider #{entry.name}: #{e.message}"
      end

      # @return [Array<Provider>] instantiated configured providers
      def providers
        configured.map { |name| provider(name) }
      end

      private

      def catalog_definition(definition)
        return [definition, :unknown] unless definition.is_a?(Hash)

        path = definition.fetch(:path) { definition.fetch("path") }
        support_level = definition[:support_level] || definition["support_level"] || :unknown
        [path, support_level]
      end

      def fetch_entry(name)
        @entries.fetch(normalize_name(name)) do
          raise Errors::ConfigurationError, "unknown provider: #{name.inspect}"
        end
      end

      def lazy_loader(path)
        lambda do
          require path
          constant_name = path.split("/").last.split("_").map(&:capitalize).join
          Sender::Core.const_get(:Providers).const_get(constant_name)
        end
      end

      def normalize_name(value)
        name = value.to_sym
        raise ArgumentError, "provider name must not be empty" if name.empty?

        name
      rescue NoMethodError
        raise ArgumentError, "provider name must be symbolizable"
      end

      def normalize_support_level(value)
        level = value.to_sym
        return level if ProviderConfiguration::SUPPORT_LEVELS.include?(level)

        raise ArgumentError, "support_level must be one of: #{ProviderConfiguration::SUPPORT_LEVELS.join(", ")}"
      rescue NoMethodError
        raise ArgumentError, "support_level must be symbolizable"
      end
    end
  end
end
