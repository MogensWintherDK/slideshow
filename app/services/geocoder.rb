require "net/http"
require "json"
require "set"

# Reverse geocoder for slideshow photos.
#
# Uses OpenStreetMap's Nominatim service (free, no API key).
# Honours Nominatim's usage policy:
#   - max 1 request / second  (we use 1.1 s spacing)
#   - identifying User-Agent
#
# Resolved coords are stored in the `locations` table so we never hit
# the network for the same point twice. The HTTP work runs in a single
# background thread so the slideshow page itself loads fast. When a
# new location is resolved, it's broadcast over Action Cable.
#
# A legacy db/locations.json file is auto-imported once into the table
# on first boot if present.
module Geocoder
  module_function

  LEGACY_PATH  = Rails.root.join("db", "locations.json")
  USER_AGENT   = "Slideshow/1.0 (local-network internal use)"
  RATE_LIMIT_S = 1.1

  @mu        = Mutex.new
  @in_flight = Set.new
  @queue     = Queue.new
  @worker    = nil
  @imported  = false

  # Round to ~110m so nearby photos share a row.
  def key_for(lat, lon)
    "#{lat.to_f.round(3)},#{lon.to_f.round(3)}"
  end

  def lookup(lat, lon)
    ensure_imported!
    row = Location.find_by(key: key_for(lat, lon))
    row && { "country" => row.country, "area" => row.area }
  rescue ActiveRecord::StatementInvalid
    nil
  end

  def resolve_async(lat, lon)
    key = key_for(lat, lon)
    @mu.synchronize do
      return if @in_flight.include?(key)
      return if Location.exists?(key: key) rescue false
      @in_flight.add(key)
    end
    @queue << [lat.to_f, lon.to_f, key]
    ensure_worker
  end

  # ── internals ──────────────────────────────────────────────────────────

  def ensure_imported!
    return if @imported
    @imported = true
    return if Location.exists?
    return unless File.exist?(LEGACY_PATH)
    data = JSON.parse(File.read(LEGACY_PATH)) rescue {}
    return if data.empty?
    now  = Time.current
    rows = data.map do |key, loc|
      { key: key,
        country: loc.is_a?(Hash) ? loc["country"] : nil,
        area:    loc.is_a?(Hash) ? loc["area"]    : nil,
        resolved_at: now }
    end
    Location.upsert_all(rows, unique_by: :key)
    Rails.logger.info("Geocoder: imported #{rows.size} rows from db/locations.json")
  rescue ActiveRecord::StatementInvalid
    @imported = false # table not yet migrated
  end

  def ensure_worker
    return if @worker&.alive?
    @worker = Thread.new do
      Thread.current.name = "geocoder-worker"
      Thread.current.abort_on_exception = false
      loop { drain_one }
    end
  end

  def drain_one
    lat, lon, key = @queue.pop
    return if Location.exists?(key: key)

    location = fetch_from_nominatim(lat, lon)
    Location.upsert(
      { key: key,
        country: location["country"],
        area:    location["area"],
        resolved_at: Time.current },
      unique_by: :key
    )
    @mu.synchronize { @in_flight.delete(key) }

    ActionCable.server.broadcast("slideshow", {
      action:   "location_resolved",
      key:      key,
      location: location
    })
  rescue => e
    Rails.logger.warn("Geocoder #{lat},#{lon} failed: #{e.class}: #{e.message}")
    @mu.synchronize { @in_flight.delete(key) }
  ensure
    sleep RATE_LIMIT_S
  end

  def fetch_from_nominatim(lat, lon)
    uri = URI("https://nominatim.openstreetmap.org/reverse")
    uri.query = URI.encode_www_form(
      format:            "json",
      lat:               lat,
      lon:               lon,
      zoom:              10,
      "accept-language": "en"
    )

    req = Net::HTTP::Get.new(uri)
    req["User-Agent"] = USER_AGENT

    res = Net::HTTP.start(uri.hostname, uri.port,
                          use_ssl: true, read_timeout: 8, open_timeout: 5) do |http|
      http.request(req)
    end

    return { "country" => nil, "area" => nil } unless res.is_a?(Net::HTTPSuccess)

    data = JSON.parse(res.body)
    addr = data["address"] || {}

    area = addr["city"]   || addr["town"]   || addr["village"] ||
           addr["hamlet"] || addr["suburb"] || addr["county"]  ||
           addr["state"]

    { "country" => addr["country"], "area" => area }
  end
end
