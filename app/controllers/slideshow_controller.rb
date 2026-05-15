class SlideshowController < ApplicationController
  include ScreenIdentity

  layout false

  skip_before_action :verify_authenticity_token, only: :update_state

  def display
    @screen = current_screen
    @group  = @screen.screen_group
    @source = @group.selected_source     # may be nil → "all photos sources"

    if @source && @source.web?
      @mode               = :web
      @web_scroll_enabled = @source.scroll_enabled
      @web_url            = if @web_scroll_enabled
                              slideshow_web_proxy_path(url: @source.url)
                            else
                              @source.url
                            end
    else
      @mode     = :photos
      @total    = photos_scope.count
      @indexing = @total.zero? && Source.photos.count.zero?
    end
  end

  # GET /slideshow/web_proxy?url=…
  # Fetches the target URL server-side and re-emits the response with
  # X-Frame-Options stripped, a <base> tag injected for relative
  # asset URLs, and a tiny postMessage scroll handler. Because the
  # iframe content is now served from our origin, the parent page can
  # scroll it directly through window.contentWindow.scrollBy().
  def web_proxy
    target = params[:url].to_s
    return head :bad_request if target.blank?

    uri = parse_http_url(target)
    return head :bad_request unless uri

    res = fetch_web(uri)
    return head :bad_gateway unless res

    response.headers.delete("X-Frame-Options")
    response.headers.delete("Content-Security-Policy")
    expires_in 60.seconds, public: false

    ctype = res["Content-Type"] || "text/html; charset=utf-8"

    if ctype.include?("text/html")
      render html: rewrite_html(res, uri).html_safe, layout: false
    else
      send_data res.body, type: ctype, disposition: "inline"
    end
  rescue => e
    Rails.logger.error("Web proxy failed: #{e.class}: #{e.message}")
    head :bad_gateway
  end

  # GET /slideshow/sources/:source_id/images/:image_id
  def image
    img = Image.find_by(id: params[:image_id], source_id: params[:source_id])
    return head :not_found unless img

    case img.source.source_type
    when "photos" then serve_photos_image(img)
    when "immich" then serve_immich_image(img)
    else               head :not_found
    end
  end

  # GET /slideshow/timeline[?source_id=K]
  def timeline
    dates = photos_scope.pluck(:taken_at).map { |t| t&.iso8601 }
    render json: { total: dates.size, dates: dates }
  end

  # GET /slideshow/playlist?from=N&count=M[&source_id=K]
  def playlist
    from  = [params[:from].to_i, 0].max
    count = params[:count].to_i.clamp(1, 100)

    scope = photos_scope
    total = scope.count

    rows = scope.offset(from).limit(count).includes(:source).to_a
    keys = rows.map(&:location_key).compact.uniq
    locs = Location.where(key: keys).index_by(&:key)

    images = rows.map do |img|
      loc = img.location_key && locs[img.location_key]
      {
        id:           img.id,
        url:          img.url,
        taken_at:     img.taken_at&.iso8601,
        location_key: img.location_key,
        location:     loc && { "country" => loc.country, "area" => loc.area },
        position:     img.position,
        source:       { id: img.source_id, name: img.source.name, type: img.source.source_type }
      }
    end

    render json: { from: from, count: images.size, total: total, images: images }
  end

  # POST /screen/state
  def update_state
    image_id = params[:image_id].presence&.to_i
    position = params[:position].presence&.to_i

    current_screen.update_columns(
      current_image_id: image_id,
      current_position: position,
      last_seen_at:     Time.current,
      primed:           true
    )

    ActionCable.server.broadcast("admin", {
      action:    "screen_state_changed",
      screen_id: current_screen.id,
      image_id:  image_id,
      image_url: image_id && Image.find_by(id: image_id)&.url
    })

    head :ok
  end

  private

  # Playlist scope covers any image-bearing source (photos or Immich).
  # If the group has selected a specific source (or a query override is
  # passed) the scope narrows to that one.
  def photos_scope
    base = Image.joins(:source)
                .where(sources: { source_type: %w[photos immich] })
                .order("sources.name ASC, images.position ASC")
    if (id = params[:source_id]).present?
      base = base.where(sources: { id: id })
    elsif current_screen.screen_group.selected_source_id.present?
      base = base.where(sources: { id: current_screen.screen_group.selected_source_id })
    end
    base
  end

  # ── Image serving ─────────────────────────────────────────────────────

  def serve_photos_image(img)
    path = img.local_path
    return head :not_found unless File.exist?(path)
    mtime = File.mtime(path)
    if stale?(etag: "#{img.id}-#{mtime.to_i}",
              last_modified: mtime, public: true)
      expires_in 1.year, public: true
      send_file path, type: "image/jpeg", disposition: "inline"
    end
  end

  # ── Web proxy helpers ─────────────────────────────────────────────────

  def parse_http_url(target)
    uri = URI.parse(target)
    return nil unless %w[http https].include?(uri.scheme)
    return nil if uri.host.blank?
    uri
  rescue URI::InvalidURIError
    nil
  end

  def fetch_web(uri, max_redirects: 3)
    redirects = 0
    loop do
      req = Net::HTTP::Get.new(uri)
      req["User-Agent"] = "Mozilla/5.0 (Slideshow Web Proxy)"
      req["Accept"]     = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"

      res = Net::HTTP.start(uri.hostname, uri.port,
                            use_ssl: uri.scheme == "https",
                            read_timeout: 15, open_timeout: 5) do |http|
        http.request(req)
      end

      if res.is_a?(Net::HTTPRedirection) && redirects < max_redirects
        uri = URI.join(uri, res["Location"])
        redirects += 1
        next
      end

      return res.is_a?(Net::HTTPSuccess) ? res : nil
    end
  rescue => e
    Rails.logger.warn("fetch_web(#{uri}) failed: #{e.class}: #{e.message}")
    nil
  end

  def rewrite_html(res, uri)
    ctype    = res["Content-Type"].to_s
    encoding = ctype[/charset=([^;\s]+)/i, 1] || "UTF-8"

    html = res.body.to_s.dup.force_encoding(encoding)
                .encode("UTF-8", invalid: :replace, undef: :replace)

    port  = (uri.port && uri.port != uri.default_port) ? ":#{uri.port}" : ""
    base  = "#{uri.scheme}://#{uri.host}#{port}/"

    inject = <<~HTML
      <base href="#{base}">
      <script>
        (function() {
          window.addEventListener("message", function(e) {
            if (e.data && e.data.type === "slideshow:scroll") {
              window.scrollBy({ top: e.data.pixels, behavior: "smooth" });
            }
          });
        })();
      </script>
    HTML

    if html =~ /<head[^>]*>/i
      html.sub(/<head[^>]*>/i) { |m| m + inject }
    else
      "<!DOCTYPE html><html><head>#{inject}</head><body>#{html}</body></html>"
    end
  end

  # Proxy the asset bytes from Immich. Cached aggressively in the
  # browser (1 year) so we only ever hit Immich once per asset version.
  def serve_immich_image(img)
    return head :not_found          unless img.external_id.present?
    return head :service_unavailable unless ImmichClient.configured?

    if stale?(etag: "immich-#{img.external_id}-#{img.updated_at.to_i}",
              last_modified: img.updated_at, public: true)
      result = ImmichClient.fetch_asset(img.external_id)
      return head :bad_gateway unless result
      bytes, ctype = result
      expires_in 1.year, public: true
      send_data bytes,
                type: ctype || "image/jpeg",
                disposition: "inline"
    end
  end
end
