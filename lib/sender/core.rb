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
