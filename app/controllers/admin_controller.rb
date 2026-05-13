class AdminController < ApplicationController
  layout "admin"

  PAGE_SIZE = 50

  def index
    @album_count    = Album.count
    @image_count    = Image.count
    @location_count = Location.count
    @setting_count  = Setting.count
    @screen_count   = Screen.count
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
    @live_screens   = Screen.includes(:current_image).order(:code)
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
    @cached_known    = Location.where.not(country: nil).count
    @cached_unknown  = Location.where(country: nil).count
  end

  def settings
    @settings = Setting.order(:key)
  end

  def groups
    @groups = ScreenGroup.includes(:screens, :selected_album).order(:id)
  end

  def screens
    @screens = Screen.includes(:current_image, screen_group: :selected_album).order(:code)
    @groups  = ScreenGroup.includes(:screens, :selected_album).order(:id)
  end

  # JSON: used by the dashboard + screens page to poll live state.
  def screens_json
    payload = Screen.includes(:current_image, screen_group: :selected_album).order(:code).map do |s|
      g = s.screen_group
      {
        id:               s.id,
        code:             s.code,
        nickname:         s.nickname,
        display_name:     s.display_name,
        last_seen_at:     s.last_seen_at&.iso8601,
        group: g && {
          id:                g.id,
          name:              g.name,
          display_name:      g.display_name,
          playing:           g.playing,
          play_mode:         g.play_mode,
          delay_seconds:     g.delay_seconds,
          selected_album:    g.selected_album && { id: g.selected_album.id, name: g.selected_album.name }
        },
        current_image: s.current_image && {
          id:       s.current_image.id,
          url:      s.current_image.url,
          filename: s.current_image.filename,
          album:    s.current_image.album.name
        }
      }
    end
    render json: { screens: payload }
  end

  def update_screen
    screen = Screen.find(params[:id])
    new_nick = params[:nickname].to_s.strip
    new_nick = nil if new_nick.empty?
    screen.update!(nickname: new_nick)
    announce_screens_changed
    redirect_to admin_screens_path, notice: "Updated."
  end

  # Delete a single screen. If that leaves an empty group behind, the
  # group is cleaned up too.
  def destroy_screen
    screen = Screen.find(params[:id])
    code   = screen.code
    group  = screen.screen_group
    screen.destroy
    group.destroy if group && group.screens.empty?
    announce_screens_changed
    redirect_to admin_screens_path, notice: "Screen #{code} deleted."
  end

  # Delete a group and every screen in it. The user gets an explicit
  # confirm from the button before this fires.
  def destroy_group
    group  = ScreenGroup.find(params[:id])
    label  = group.display_name
    screens_destroyed = group.screens.count
    group.screens.destroy_all
    group.destroy
    announce_screens_changed
    redirect_to admin_groups_path, notice: "Deleted group #{label} (#{screens_destroyed} screen#{'s' if screens_destroyed != 1})."
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

  def announce_screens_changed
    ActionCable.server.broadcast("slideshow", {
      action:  "screens_changed",
      screens: Screen.includes(:current_image).order(:code).map(&:to_remote_json),
      groups:  ScreenGroup.includes(:screens).order(:id).map(&:to_remote_json)
    })
  end
end
