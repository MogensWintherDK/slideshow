class SlideshowController < ApplicationController
  layout false

  # The display page is now a thin shell. All image data is fetched
  # incrementally by the client via #playlist.
  def display
    @settings    = SettingsStore.read
    @total       = playlist_scope.count
    @indexing    = @total.zero? && Album.count.zero?
    @albums      = Album.order(:name).pluck(:id, :name, :album_type)
  end

  # GET /slideshow/timeline[?album_id=K]
  #
  # Returns just the per-position taken_at as an ISO-string array.
  # The slideshow uses this on boot to render every marker on the
  # timeline up-front, without waiting for the full playlist to page in.
  def timeline
    dates = playlist_scope.pluck(:taken_at).map { |t| t&.iso8601 }
    render json: { total: dates.size, dates: dates }
  end

  # GET /slideshow/playlist?from=N&count=M[&album_id=K]
  #
  # Returns metadata for a slice of the global playlist (or a single
  # album if album_id is provided). Locations are joined in if cached.
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
        url:          img.url,
        taken_at:     img.taken_at&.iso8601,
        location_key: img.location_key,
        location:     loc && { "country" => loc.country, "area" => loc.area },
        album:        { id: img.album_id, name: img.album.name, type: img.album.album_type }
      }
    end

    render json: { from: from, count: images.size, total: total, images: images }
  end

  private

  # The order across the whole library: by album name, then by intra-album
  # position. Filtering by selected_album_id (a future setting) is honoured.
  def playlist_scope
    base = Image.joins(:album).order("albums.name ASC, images.position ASC")
    if (id = params[:album_id]).present?
      base = base.where(albums: { id: id })
    elsif (id = SettingsStore.read["selected_album_id"]).present?
      base = base.where(albums: { id: id })
    end
    base
  end
end
