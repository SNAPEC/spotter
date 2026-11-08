require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_view/railtie"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Spotter
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    config.i18n.default_locale = :fr

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # Day-based deadlines (draft expiry, editing window, ownership cutoff, purges) roll over at midnight in
    # France. Timestamps stay stored in UTC.
    config.time_zone = "Europe/Paris"
    # config.eager_load_paths << Rails.root.join("extras")

    # Its routes serve and accept files without authentication. Files will go through our own authorised
    # controllers.
    config.active_storage.draw_routes = false

    # A finished job row keeps its arguments, a user's GlobalID among them, and the time it ran: it would
    # date a mail in the provider's log. Deleted as soon as the job has run, in every environment.
    config.solid_queue.preserve_finished_jobs = false

    # Don't generate system test files.
    config.generators.system_tests = nil
  end
end
