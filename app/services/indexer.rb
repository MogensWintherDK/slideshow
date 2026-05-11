require "exifr/jpeg"

# Disk → database sync for local albums.
#
# Scans public/slides/:
#   - Each subdirectory becomes a local Album (name = directory name).
#   - JPEGs directly in public/slides/ are kept in a "Default" album.
#   - New files get an EXIF-read on insert. We never re-read EXIF for
#     existing rows unless the file is deleted and re-indexed.
#   - Files removed from disk → corresponding image rows are deleted.
#   - Subdirectories that vanish → albums (and their images via FK cascade)
#     are removed.
#
# Runs once on first slideshow request, then re-scans every 5 minutes
# in a background thread. The worker properly checks out an
# ActiveRecord connection from the pool.
module Indexer
  module_function

  SLIDES_ROOT      = Rails.root.join("public", "slides")
  DEFAULT_ALBUM    = { name: "Default", path: "" }.freeze
  RESCAN_INTERVAL  = 5 * 60     # seconds
  IMAGE_GLOB       = /\.jpe?g\z/i

  @started   = false
  @mu        = Mutex.new
  @worker    = nil

  # ── Public API ─────────────────────────────────────────────────────────

  def start_once
    @mu.synchronize do
      return if @started
      @started = true
    end
    @worker = Thread.new { background_loop }
  end

  # One-shot synchronous reindex; used at boot and from rails runner.
  def run
    ActiveRecord::Base.connection_pool.with_connection do
      sync_default_album
      sync_subfolder_albums
      remove_orphan_albums
    end
  end

  # ── Internals ──────────────────────────────────────────────────────────

  def background_loop
    Thread.current.name = "indexer"
    Thread.current.abort_on_exception = false
    # Small delay so the initial DB/HTTP boot can settle.
    sleep 1
    loop do
      begin
        run
      rescue => e
        Rails.logger.error("Indexer error: #{e.class}: #{e.message}")
      end
      sleep RESCAN_INTERVAL
    end
  end

  # JPEGs directly under public/slides/ live in a "Default" album.
  def sync_default_album
    return unless File.directory?(SLIDES_ROOT)
    files = list_images(SLIDES_ROOT)
    if files.empty?
      # Drop the default album if it exists and is empty
      Album.local.where(path: "").find_each { |a| a.destroy if a.images.empty? }
      return
    end
    album = upsert_album(DEFAULT_ALBUM[:name], DEFAULT_ALBUM[:path])
    sync_album_files(album, SLIDES_ROOT, files)
  end

  def sync_subfolder_albums
    return unless File.directory?(SLIDES_ROOT)
    Dir.children(SLIDES_ROOT).sort.each do |entry|
      dir = SLIDES_ROOT.join(entry)
      next unless File.directory?(dir)
      album = upsert_album(entry, entry)
      sync_album_files(album, dir, list_images(dir))
    end
  end

  def upsert_album(name, path)
    album = Album.find_or_initialize_by(album_type: "local", path: path)
    album.name = name if album.name != name
    album.save! if album.changed?
    album
  end

  def list_images(dir)
    Dir.children(dir).select { |f| f =~ IMAGE_GLOB }.sort
  end

  def sync_album_files(album, dir, files)
    # Insert / update positions
    files.each_with_index do |filename, idx|
      image = Image.find_or_initialize_by(album_id: album.id, filename: filename)
      if image.new_record?
        meta = read_exif(dir.join(filename))
        image.taken_at     = meta[:date]
        image.latitude     = meta[:lat]
        image.longitude    = meta[:lon]
        image.location_key = meta[:location_key]
        if meta[:lat] && meta[:lon]
          Geocoder.resolve_async(meta[:lat], meta[:lon])
        end
      end
      image.position = idx
      image.save! if image.changed?
    end

    # Delete rows for files no longer on disk
    Image.where(album_id: album.id).where.not(filename: files).delete_all
  end

  def remove_orphan_albums
    Album.local.find_each do |album|
      # Default album lives at the slides root; only delete if root is gone
      dir = album.path.present? ? SLIDES_ROOT.join(album.path) : SLIDES_ROOT
      album.destroy unless File.directory?(dir)
    end
  end

  def read_exif(path)
    exif = EXIFR::JPEG.new(path.to_s)
    date = exif.date_time_original || File.mtime(path)
    lat  = exif.gps&.latitude
    lon  = exif.gps&.longitude
    key  = (lat && lon) ? Geocoder.key_for(lat, lon) : nil
    { date: date, lat: lat, lon: lon, location_key: key }
  rescue StandardError => e
    Rails.logger.warn("EXIF read failed for #{path}: #{e.class}: #{e.message}")
    { date: (File.mtime(path) rescue nil), lat: nil, lon: nil, location_key: nil }
  end
end
