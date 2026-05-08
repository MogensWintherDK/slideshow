require "net/http"
require "json"
require "set"
require "fileutils"

# Reverse geocoder for slideshow photos.
#
# Uses OpenStreetMap's Nominatim service (free, no API key).
# Honours Nominatim's usage policy:
#   - max 1 request / second  (we use 1.1s spacing)
#   - identifying User-Agent
#
# Resolved coords are cached to db/locations.json so we never hit the
# network for the same point twice. The actual HTTP work runs in a
# single background thread so the slideshow page itself loads fast.
# When a new location is resolved, it's broadcast over Action Cable
# so the slideshow can update the label live.
module Geocoder
  module_function

  CACHE_PATH   = Rails.root.join("db", "locations.json")
  USER_AGENT   = "Slideshow/1.0 (local-network internal use)"
  RATE_LIMIT_S = 1.1

  @cache_mu  = Mutex.new
  @cache     = nil
  @in_flight = Set.new
  @queue     = Queue.new
  @worker    = nil

  # Round to ~110m so nearby photos share a cache entry
  def key_for(lat, lon)
    "#{lat.to_f.round(3)},#{lon.to_f.round(3)}"
  end

  def lookup(lat, lon)
    cache[key_for(lat, lon)]
  end

  # Queue a coord for background resolution if we don't already have it.
  def resolve_async(lat, lon)
    key = key_for(lat, lon)
    @cache_mu.synchronize do
      return if cache.key?(key) || @in_flight.include?(key)
      @in_flight.add(key)
    end
    @queue << [lat.to_f, lon.to_f, key]
    ensure_worker
  end

  # ── internals ──────────────────────────────────────────────────────────

  def cache
    @cache ||= load_cache
  end

  def load_cache
    return {} unless File.exist?(CACHE_PATH)
    JSON.parse(File.read(CACHE_PATH))
  rescue JSON::ParserError
    {}
  end

  def persist_cache
    FileUtils.mkdir_p(File.dirname(CACHE_PATH))
    File.write(CACHE_PATH, JSON.pretty_generate(@cache))
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
    return if @cache_mu.synchronize { cache.key?(key) }

    location = fetch_from_nominatim(lat, lon)
    @cache_mu.synchronize do
      cache[key] = location
      @in_flight.delete(key)
      persist_cache
    end

    ActionCable.server.broadcast("slideshow", {
      action:   "location_resolved",
      key:      key,
      location: location
    })
  rescue => e
    Rails.logger.warn("Geocoder #{lat},#{lon} failed: #{e.class}: #{e.message}")
    @cache_mu.synchronize { @in_flight.delete(key) }
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
