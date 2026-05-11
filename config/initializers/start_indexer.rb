# Kick off the background indexer once the Rails server is running.
# We deliberately skip this when:
#   - Running rake tasks (migrations, etc.)
#   - Running rails console
# so we don't spawn a thread the user didn't ask for.

Rails.application.config.after_initialize do
  next if defined?(Rails::Console)
  next if File.basename($PROGRAM_NAME) == "rake"
  next if ENV["SKIP_INDEXER"] == "1"

  # Defer until the first request to avoid blocking boot.
  # We hook into the middleware to start exactly once.
  ActiveSupport.on_load(:action_controller) do
    # Module trick: only ever start the thread once even if reloaded.
    Indexer.start_once if defined?(Indexer)
  end
end
