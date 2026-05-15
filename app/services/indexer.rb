require "exifr/jpeg"

# Disk → database sync for photos sources.
#
# Scans slides/ at the project root:
#   - Each subdirectory becomes a Source of type "photos" (name = directory).
#   - JPEGs directly in slides/ are kept in a "Default" photos source.
#   - New files get an EXIF-read on insert. We also re-read EXIF if a
#     file's mtime is newer than the row's updated_at.
#   - Files removed from disk are deleted from `images`.
#   - Subdirectories that vanish → photos sources (and their images via
#     FK cascade) are removed. Web sources are never touched here.
module Indexer
  module_function

  SLIDES_ROOT     = Image.slides_root
  DEFAULT_SOURCE  = { name: "Default", path: "" }.freeze
  RESCAN_INTERVAL = 5 * 60     # seconds
  IMAGE_GLOB      = /\.jpe?g\z/i

  @started     = false
  @mu          = Mutex.new
  @worker      = nil
  @last_run_at = nil
  @last_error  = nil

  class << self
    attr_reader :last_run_at, :last_error
  end

  # ── Public API ─────────────────────────────────────────────────────────

  def start_once
    @mu.synchronize do
      return if @started
      @started = true
    end
    @worker = Thread.new { background_loop }
  end

  def run
    ActiveRecord::Base.connection_pool.with_connection do
      @source_changes = 0
      sync_default_source
      sync_subfolder_sources
      @source_changes += remove_orphan_sources
      sync_all_immich_sources
      broadcast_sources_changed if @source_changes.positive?
    end
    @last_run_at = Time.current
    @last_error  = nil
  rescue => e
    @last_error  = "#{e.class}: #{e.message}"
    raise
  end

  # Sync every Immich source. Errors on one source don't stop the others.
  def sync_all_immich_sources
    return unless ImmichClient.configured?
    Source.immich.find_each do |source|
      begin
        sync_immich_source(source)
      rescue => e
        Rails.logger.warn("Immich sync failed for source ##{source.id}: #{e.class}: #{e.message}")
      end
    end
  end

  # Pull the album's current asset list from Immich and reconcile it
  # against the images table. Called from the periodic indexer loop and
  # also synchronously from the admin form when a source is first added.
  def sync_immich_source(source)
    return unless ImmichClient.configured?
    return unless source.immich? && source.external_id.present?

    album       = ImmichClient.album(source.external_id)
    assets      = album["assets"] || []
    asset_uuids = []

    # Update the source's display name from Immich if we don't already
    # have one set (or it matches Immich's previous name).
    if album["albumName"].present? && source.name.blank?
      source.update_columns(name: album["albumName"])
    end

    assets.each do |asset|
      uuid = asset["id"]
      next unless uuid.present?
      asset_uuids << uuid

      image = Image.find_or_initialize_by(source_id: source.id, external_id: uuid)
      exif  = asset["exifInfo"] || {}

      # Use the UUID as filename so the (source_id, filename) uniqueness
      # holds even when two assets have the same original filename.
      image.filename     = uuid
      image.taken_at     = parse_immich_time(
                            exif["dateTimeOriginal"] ||
                            asset["fileCreatedAt"] ||
                            asset["createdAt"])
      image.latitude     = exif["latitude"]
      image.longitude    = exif["longitude"]
      image.location_key = (image.latitude && image.longitude) ? Geocoder.key_for(image.latitude, image.longitude) : nil

      if image.latitude && image.longitude
        Geocoder.resolve_async(image.latitude, image.longitude)
      end

      image.save! if image.changed?
    end

    # Remove rows whose asset is no longer in the Immich album.
    Image.where(source_id: source.id).where.not(external_id: asset_uuids).delete_all

    # Renumber positions chronologically (same rule as photos sources).
    ordered = Image.where(source_id: source.id)
                   .order(Arel.sql("taken_at IS NULL, taken_at ASC, filename ASC"))
                   .pluck(:id)
    ordered.each.with_index do |id, idx|
      Image.where(id: id).where.not(position: idx).update_all(position: idx)
    end
  end

  def parse_immich_time(s)
    return nil if s.blank?
    Time.parse(s.to_s)
  rescue ArgumentError
    nil
  end

  # ── Internals ──────────────────────────────────────────────────────────

  def background_loop
    Thread.current.name = "indexer"
    Thread.current.abort_on_exception = false
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

  def sync_default_source
    return unless File.directory?(SLIDES_ROOT)
    files = list_images(SLIDES_ROOT)
    if files.empty?
      Source.photos.where(path: "").find_each { |s| s.destroy if s.images.empty? }
      return
    end
    source = upsert_source(DEFAULT_SOURCE[:name], DEFAULT_SOURCE[:path])
    sync_source_files(source, SLIDES_ROOT, files)
  end

  def sync_subfolder_sources
    return unless File.directory?(SLIDES_ROOT)
    Dir.children(SLIDES_ROOT).sort.each do |entry|
      dir = SLIDES_ROOT.join(entry)
      next unless File.directory?(dir)
      source = upsert_source(entry, entry)
      sync_source_files(source, dir, list_images(dir))
    end
  end

  def upsert_source(name, path)
    source = Source.find_or_initialize_by(source_type: "photos", path: path)
    was_new = source.new_record?
    source.name = name if source.name != name
    source.save! if source.changed?
    @source_changes ||= 0
    @source_changes += 1 if was_new
    source
  end

  def list_images(dir)
    Dir.children(dir).select { |f| f =~ IMAGE_GLOB }.sort
  end

  def sync_source_files(source, dir, files)
    files.each do |filename|
      image      = Image.find_or_initialize_by(source_id: source.id, filename: filename)
      file_mtime = File.mtime(dir.join(filename)) rescue nil

      needs_reread = image.new_record? ||
                     (file_mtime && image.updated_at && file_mtime > image.updated_at)

      if needs_reread
        meta = read_exif(dir.join(filename))
        image.taken_at     = meta[:date]
        image.latitude     = meta[:lat]
        image.longitude    = meta[:lon]
        image.location_key = meta[:location_key]
        if meta[:lat] && meta[:lon]
          Geocoder.resolve_async(meta[:lat], meta[:lon])
        end
      end

      if image.changed?
        image.save!
      elsif needs_reread
        image.touch
      end
    end

    Image.where(source_id: source.id).where.not(filename: files).delete_all

    # Renumber positions chronologically by taken_at.
    ordered = Image.where(source_id: source.id)
                   .order(Arel.sql("taken_at IS NULL, taken_at ASC, filename ASC"))
                   .pluck(:id)
    ordered.each.with_index do |id, idx|
      Image.where(id: id).where.not(position: idx).update_all(position: idx)
    end
  end

  def remove_orphan_sources
    removed = 0
    # Only consider photos sources — web sources are user-managed.
    Source.photos.find_each do |source|
      dir = source.path.present? ? SLIDES_ROOT.join(source.path) : SLIDES_ROOT
      next if File.directory?(dir)
      source.destroy
      removed += 1
    end
    removed
  end

  def broadcast_sources_changed
    sources = Source.order(:name).pluck(:id, :name, :source_type, :url).map do |id, name, type, url|
      { id: id, name: name, type: type, url: url }
    end
    ActionCable.server.broadcast("slideshow", {
      action:  "sources_changed",
      sources: sources
    })
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
