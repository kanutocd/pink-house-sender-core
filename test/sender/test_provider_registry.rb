# frozen_string_literal: true

require "test_helper"

module Sender
  module Core
    class TestProviderRegistry < Minitest::Test
      class FakeProvider < Sender::Core::Provider; end

      def test_starts_with_an_empty_catalog_without_loading_adapters
        registry = ProviderRegistry.new

        assert_empty registry.supported
        assert_empty registry.configured
      end

      def test_registers_configures_and_lazily_instantiates_provider
        loaded = false
        registry = ProviderRegistry.new(catalog: {})
        loader = lambda do
          loaded = true
          FakeProvider
        end
        registry.register(:fake, loader: loader, capabilities: [:sms])

        refute loaded
        configuration = registry.configure("fake", settings: { token: "secret" })

        refute loaded
        provider = registry.provider(:fake)

        assert loaded
        assert_equal({ token: "secret" }, configuration.settings)
        assert_equal [:fake], registry.configured
        assert_instance_of FakeProvider, provider
      end

      def test_exposes_advisory_provider_metadata_without_affecting_configuration
        registry = ProviderRegistry.new(catalog: { fake: { path: "fake/provider", support_level: :experimental } })
        registry.register(:custom, loader: -> { FakeProvider }, support_level: :deprecated)

        assert_equal :experimental, registry.provider_metadata(:fake).fetch(:support_level)
        assert_equal :deprecated, registry.provider_metadata(:custom).fetch(:support_level)
        registry.configure(:fake)

        assert_equal [:fake], registry.configured
      end

      def test_returns_all_configured_provider_instances
        registry = ProviderRegistry.new(catalog: {})
        registry.register(:first, loader: -> { FakeProvider })
        registry.register(:second, loader: -> { FakeProvider })
        registry.configure(:first)
        registry.configure(:second)

        assert_equal %i[first second], registry.providers.map(&:name)
      end

      def test_rejects_unknown_duplicate_and_invalid_registrations
        registry = ProviderRegistry.new(catalog: {})

        assert_raises(ArgumentError) { registry.register(:fake, loader: Object.new) }
        registry.register(:fake, loader: -> { FakeProvider })
        assert_raises(ArgumentError) { registry.register(:fake, loader: -> { FakeProvider }) }
        assert_raises(Errors::ConfigurationError) { registry.configure(:missing) }
        assert_raises(ArgumentError) { registry.register(nil, loader: -> { FakeProvider }) }
        assert_raises(ArgumentError) { registry.register("", loader: -> { FakeProvider }) }
        assert_raises(ArgumentError) { registry.register(:not_an_array, loader: -> { FakeProvider }, capabilities: {}) }
        assert_raises(ArgumentError) { registry.register(:bad, loader: -> { FakeProvider }, capabilities: [nil]) }
      end

      def test_rejects_loader_that_does_not_return_a_class
        registry = ProviderRegistry.new(catalog: {})
        registry.register(:invalid, loader: -> { Object.new })
        registry.configure(:invalid)

        assert_raises(Errors::ConfigurationError) { registry.provider(:invalid) }
      end

      def test_wraps_missing_adapter_load_errors
        registry = ProviderRegistry.new(catalog: {})
        registry.register(:missing, loader: -> { raise LoadError, "missing dependency" })
        registry.configure(:missing)

        error = assert_raises(Errors::ConfigurationError) { registry.provider(:missing) }

        assert_match(/could not load provider missing/, error.message)
      end
    end
  end
end
