require "net/http"
require "json"
require "uri"

# Thin wrapper around the Immich HTTP API.
#
# Configuration via environment variables:
#
#   IMMICH_BASE_URL   default "https://immich.mowin.dk"
#   IMMICH_API_KEY    required for any call to succeed
#
# Set them before launching bin/start, e.g.
#   IMMICH_API_KEY=xxxxxxxx bin/start
module ImmichClient
  module_function

  DEFAULT_BASE_URL = "https://immich.mowin.dk".freeze
  TIMEOUT          = 30

  class Error     < StandardError; end
  class AuthError < Error; end

  def configured?
    api_key.present?
  end

  # Configuration resolves in this order:
  #   1. The Settings table (set via /admin/settings — live, no restart)
  #   2. Environment variable
  #   3. The hard-coded default (for base_url only)
  def api_key
    stored = SettingsStore.read["immich_api_key"]
    return stored if stored.present?
    env = ENV["IMMICH_API_KEY"]
    env if env.present?
  end

  def base_url
    stored = SettingsStore.read["immich_base_url"]
    return stored if stored.present?
    env = ENV["IMMICH_BASE_URL"]
    return env if env.present?
    DEFAULT_BASE_URL
  end

  # List albums on the server. Returns an Array of
  # { id:, name:, asset_count:, shared: } hashes.
  def albums
    body = http_get("/api/albums")
    JSON.parse(body).map do |a|
      {
        id:          a["id"],
        name:        a["albumName"] || a["name"],
        asset_count: a["assetCount"] || (a["assets"] || []).size,
        shared:      a["shared"] || false
      }
    end
  end

  # Get one album with its assets. Returns the parsed JSON hash.
  def album(uuid)
    JSON.parse(http_get("/api/albums/#{uuid}"))
  end

  # Fetch the bytes for a single asset. Returns [bytes, content_type] or nil.
  # We use the "preview" size by default (≈1440px max edge) — plenty for
  # most TVs and far smaller than the original.
  def fetch_asset(asset_uuid, size: "preview")
    path = case size
           when "original"  then "/api/assets/#{asset_uuid}/original"
           when "thumbnail" then "/api/assets/#{asset_uuid}/thumbnail?size=thumbnail"
           else                  "/api/assets/#{asset_uuid}/thumbnail?size=preview"
           end
    uri  = build_uri(path)
    req  = Net::HTTP::Get.new(uri)
    req["x-api-key"] = api_key
    req["Accept"]    = "*/*"

    res = Net::HTTP.start(uri.hostname, uri.port,
                          use_ssl: uri.scheme == "https",
                          read_timeout: 60, open_timeout: 10) do |http|
      http.request(req)
    end

    return nil unless res.is_a?(Net::HTTPSuccess)
    [res.body, res["Content-Type"]]
  rescue => e
    Rails.logger.warn("Immich fetch_asset(#{asset_uuid}) failed: #{e.class}: #{e.message}")
    nil
  end

  # ── internals ──────────────────────────────────────────────────────────

  def http_get(path)
    raise AuthError, "IMMICH_API_KEY is not set" unless configured?

    uri = build_uri(path)
    req = Net::HTTP::Get.new(uri)
    req["x-api-key"] = api_key
    req["Accept"]    = "application/json"

    res = Net::HTTP.start(uri.hostname, uri.port,
                          use_ssl: uri.scheme == "https",
                          read_timeout: TIMEOUT, open_timeout: 10) do |http|
      http.request(req)
    end

    raise AuthError, "Immich rejected the API key (HTTP #{res.code})" if res.code.to_i == 401
    unless res.is_a?(Net::HTTPSuccess)
      raise Error, "Immich #{path}: HTTP #{res.code} #{res.body.to_s[0..200]}"
    end
    res.body
  end

  def build_uri(path)
    URI("#{base_url}#{path}")
  end
end
