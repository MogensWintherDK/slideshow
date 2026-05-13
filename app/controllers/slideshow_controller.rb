class SlideshowController < ApplicationController
  include ScreenIdentity

  layout false

  skip_before_action :verify_authenticity_token, only: :update_state

  def display
    @screen   = current_screen
    @group    = @screen.screen_group
    @total    = playlist_scope.count
    @indexing = @total.zero? && Album.count.zero?
  end

  def image
    img = Image.find_by(id: params[:image_id], album_id: params[:album_id])
    return head :not_found unless img
    return head :not_found unless img.album.album_type == "local"

    path = img.local_path
    return head :not_found unless File.exist?(path)

    mtime = File.mtime(path)
    if stale?(etag: "#{img.id}-#{mtime.to_i}",
              last_modified: mtime,
              public: true)
      expires_in 1.year, public: true
      send_file path, type: "image/jpeg", disposition: "inline"
    end
  end

  def timeline
    dates = playlist_scope.pluck(:taken_at).map { |t| t&.iso8601 }
    render json: { total: dates.size, dates: dates }
  end

  def playlist
    from  = [params[:from].to_i, 0].max
    count = params[:count].to_i.clamp(1, 100)

    scope = playlist_scope
    total = scope.count

    rows = scope.offset(from).limit(count).includes(:album).to_a
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
        album:        { id: img.album_id, name: img.album.name, type: img.album.album_type }
      }
    end

    render json: { from: from, count: images.size, total: total, images: images }
  end

  # POST /screen/state — display reports its current image after each advance.
  def update_state
    image_id = params[:image_id].presence&.to_i
    position = params[:position].presence&.to_i

    # Reporting a current image also primes the screen — the display is
    # actively showing something, so on subsequent reloads it should pick
    # up where it left off rather than dropping back to the splash.
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

  # Playlist scope honours the screen's group's selected_album_id
  # (query override still wins for ad-hoc requests).
  def playlist_scope
    base = Image.joins(:album).order("albums.name ASC, images.position ASC")
    if (id = params[:album_id]).present?
      base = base.where(albums: { id: id })
    elsif (id = current_screen.screen_group.selected_album_id).present?
      base = base.where(albums: { id: id })
    end
    base
  end
end
