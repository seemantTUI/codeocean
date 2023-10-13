# frozen_string_literal: true

require_relative 'boot'

require 'rails/all'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

require 'telegraf/rails'
require_relative '../lib/middleware/web_socket_sentry_headers'

module CodeOcean
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.0

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.

    # Set Time.zone default to the specified zone and make Active Record auto-convert to this zone.
    # Run "rake -D time" for a list of tasks for finding time zone names. Default is UTC.
    config.time_zone = ENV.fetch('RAILS_TIME_ZONE', 'UTC')

    # The default locale is :en and all translations from config/locales/*.rb,yml are auto loaded.
    # config.i18n.load_path += Dir[Rails.root.join('my', 'locales', '*.{rb,yml}').to_s]
    # config.i18n.default_locale = :de
    config.i18n.available_locales = %i[de en]

    extra_paths = [
      Rails.root.join('lib'),
    ]

    # Add generators, they don't have a module structure that matches their directory structure.
    extra_paths << Rails.root.join('lib/generators')

    config.add_autoload_paths_to_load_path = false
    config.autoload_paths += extra_paths
    config.eager_load_paths += extra_paths

    config.relative_url_root = ENV.fetch('RAILS_RELATIVE_URL_ROOT', '/').to_s

    config.action_cable.mount_path = "#{ENV.fetch('RAILS_RELATIVE_URL_ROOT', '')}/cable"

    # Disable concurrent ActionCable workers to ensure ACE change events keep their order
    config.action_cable.worker_pool_size = 1

    config.telegraf.tags = {application: 'codeocean'}

    config.after_initialize do
      # Initialize the counters according to the db
      Prometheus::Controller.initialize_metrics

      # Initialize the runner environment
      Runner.strategy_class.initialize_environment
    end

    # Specify default options for Rails generators
    config.generators do |g|
      g.orm :active_record, primary_key_type: :uuid
    end

    # Allow tables in addition to existing default tags
    config.action_view.sanitized_allowed_tags = ActionView::Base.sanitized_allowed_tags + %w[table thead tbody tfoot td tr details summary]

    # Extract Sentry-related parameters from WebSocket connection
    config.middleware.insert_before 0, Middleware::WebSocketSentryHeaders
  end
end
