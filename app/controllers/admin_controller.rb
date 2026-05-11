class AdminController < ApplicationController
  layout "admin"

  PAGE_SIZE = 50

  def index
    @album_count    = Album.count
    @image_count    = Image.count
    @location_count = Location.count
    @setting_count  = Setting.count
    @albums_by_type = Album.group(:album_type).count
    @top_albums     = Album.left_joins(:images)
                           .select("albums.*, COUNT(images.id) AS image_count")
                           .group("albums.id")
                           .order("image_count DESC, albums.name ASC")
                           .limit(10)
    @recent_images  = Image.includes(:album).order(updated_at: :desc).limit(8)
    @indexer_last   = Indexer.last_run_at
    @indexer_error  = Indexer.last_error
    @slides_root    = Image.slides_root.to_s
  end

  def albums
    @albums = Album.left_joins(:images)
                   .select("albums.*, COUNT(images.id) AS image_count")
                   .group("albums.id")
                   .order(:name)
  end

  def album_show
    @album       = Album.find(params[:id])
    @page, @per  = pagination
    @total       = @album.images.count
    @images      = @album.images.order(:position).offset((@page - 1) * @per).limit(@per)
    @total_pages = pages(@total, @per)
  end

  def images
    @page, @per  = pagination
    @total       = Image.count
    @images      = Image.includes(:album)
                        .order("albums.name ASC, images.position ASC")
                        .joins(:album)
                        .offset((@page - 1) * @per)
                        .limit(@per)
    @total_pages = pages(@total, @per)
  end

  def locations
    @page, @per  = pagination
    @total       = Location.count
    @locations   = Location.order(resolved_at: :desc).offset((@page - 1) * @per).limit(@per)
    @total_pages = pages(@total, @per)
    @cached_known     = Location.where.not(country: nil).count
    @cached_unknown   = Location.where(country: nil).count
  end

  def settings
    @settings = Setting.order(:key)
  end

  def reindex
    Indexer.run
    redirect_to admin_path, notice: "Re-indexed."
  rescue => e
    redirect_to admin_path, alert: "Reindex failed: #{e.class}: #{e.message}"
  end

  private

  def pagination
    page = [params[:page].to_i, 1].max
    [page, PAGE_SIZE]
  end

  def pages(total, per)
    return 1 if per.zero?
    ((total.to_f) / per).ceil.clamp(1, Float::INFINITY)
  end
end
