require "json"

# Key/value settings backed by the `settings` table.
# Values are JSON-encoded so we can round-trip booleans, strings, and nil.
#
# On first read, if the table is empty and a legacy db/settings.json
# file exists, its contents are imported automatically.
module SettingsStore
  module_function

  LEGACY_PATH = Rails.root.join("db", "settings.json")
  DEFAULTS    = {
    "birthday_mode" => false,
    "birthday"      => nil,    # ISO date string, e.g. "2018-04-12"
    "play_mode"     => "linear" # "linear" or "random"
  }.freeze

  def read
    ensure_imported!
    rows = Setting.pluck(:key, :value).to_h
    DEFAULTS.merge(rows.transform_values { |v| decode(v) })
  rescue ActiveRecord::StatementInvalid
    # Table not migrated yet
    DEFAULTS.dup
  end

  def write(updates)
    ensure_imported!
    now = Time.current
    rows = updates.map do |k, v|
      { key: k.to_s, value: encode(v), created_at: now, updated_at: now }
    end
    Setting.upsert_all(rows, unique_by: :key) unless rows.empty?
    read
  end

  # ── internals ──────────────────────────────────────────────────────────

  def encode(v) = v.to_json
  def decode(v) = (JSON.parse(v) rescue v)

  def ensure_imported!
    return if @imported
    @imported = true
    return if Setting.exists?
    return unless File.exist?(LEGACY_PATH)
    data = JSON.parse(File.read(LEGACY_PATH)) rescue {}
    return if data.empty?
    now  = Time.current
    rows = data.map { |k, v| { key: k, value: encode(v), created_at: now, updated_at: now } }
    Setting.upsert_all(rows, unique_by: :key)
    Rails.logger.info("SettingsStore: imported #{rows.size} rows from db/settings.json")
  rescue ActiveRecord::StatementInvalid
    @imported = false # try again after migrations
  end
end
