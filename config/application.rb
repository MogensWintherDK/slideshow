require_relative "boot"

require "rails"
# Pick the frameworks we actually use - skip ActionMailer, ActiveJob, etc.
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "action_cable/engine"
require "rails/test_unit/railtie"

Bundler.require(*Rails.groups)

module Slideshow
  class Application < Rails::Application
    config.load_defaults 7.0
    config.autoload_lib(ignore: %w[assets tasks]) if config.respond_to?(:autoload_lib)

    # Allow connections from any host (needed for phone on local network)
    config.hosts.clear

    # Action Cable: skip CSRF on the WebSocket since this is internal use only
    config.action_cable.disable_request_forgery_protection = true

    # Don't generate routes for assets - we don't have an asset pipeline
    config.api_only = false
  end
end
