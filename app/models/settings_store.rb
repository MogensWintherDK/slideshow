require "json"

# Tiny file-backed key/value store for slideshow settings.
# We don't need an ActiveRecord table for two scalars.
module SettingsStore
  module_function

  PATH     = Rails.root.join("db", "settings.json")
  MUTEX    = Mutex.new
  DEFAULTS = {
    "birthday_mode" => false,
    "birthday"      => nil   # ISO date string, e.g. "2018-04-12"
  }.freeze

  def read
    MUTEX.synchronize do
      return DEFAULTS.dup unless File.exist?(PATH)
      DEFAULTS.merge(JSON.parse(File.read(PATH)))
    end
  rescue JSON::ParserError
    DEFAULTS.dup
  end

  def write(updates)
    MUTEX.synchronize do
      current = File.exist?(PATH) ? (JSON.parse(File.read(PATH)) rescue {}) : {}
      merged  = DEFAULTS.merge(current).merge(updates.transform_keys(&:to_s))
      FileUtils.mkdir_p(File.dirname(PATH))
      File.write(PATH, JSON.pretty_generate(merged))
      merged
    end
  end
end
