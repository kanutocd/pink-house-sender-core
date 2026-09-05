# frozen_string_literal: true

require_relative "core/version"

# Top-level namespace for sender-related libraries.
module Sender
  # Namespace for sender-related libraries.
  module Core
    # Channel-neutral delivery runtime shared by sender gems.
    # Base error raised by sender-core.
    class Error < StandardError; end
  end
end

require_relative "core/capabilities"
require_relative "core/errors"
require_relative "core/message"
require_relative "core/delivery"
require_relative "core/delivery_event"
require_relative "core/provider_configuration"
require_relative "core/provider"
require_relative "core/state_store"
require_relative "core/observability"
require_relative "core/circuit_breaker"
require_relative "core/health"
require_relative "core/election"
require_relative "core/provider_registry"
require_relative "core/router"
require_relative "core/http"
