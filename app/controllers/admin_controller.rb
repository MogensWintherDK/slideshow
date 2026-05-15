class AdminController < ApplicationController
  layout "admin"

  PAGE_SIZE = 50

  def index
    @source_count   = Source.count
    @image_count    = Image.count
    @location_count = Location.count
    @screen_count   = Screen.count
    @sources_by_type = Source.group(:source_type).count
    @top_sources    = Source.left_joins(:images)
                            .select("sources.*, COUNT(images.id) AS image_count")
                            .group("sources.id")
                            .order("image_count DESC, sources.name ASC")
                            .limit(10)
    @recent_images  = Image.includes(:source).order(updated_at: :desc).limit(8)
    @indexer_last   = Indexer.last_run_at
    @indexer_error  = Indexer.last_error
    @slides_root    = Image.slides_root.to_s
    @live_screens   = Screen.includes(:current_image).order(:code)
  end

  def sources
    @sources = Source.left_joins(:images)
                     .select("sources.*, COUNT(images.id) AS image_count")
                     .group("sources.id")
                     .order(:name)
    @new_source = Source.new(source_type: "photos")
  end

  def create_source
    type = params[:source_type].to_s
    type = "photos" unless Source::TYPES.include?(type)

    attrs = { source_type: type, name: params[:name].to_s.strip, path: "" }
    case type
    when "photos"
      attrs[:path] = params[:path].to_s.strip
    when "web"
      attrs[:url]            = params[:url].to_s.strip
      attrs[:scroll_enabled] = ActiveModel::Type::Boolean.new.cast(params[:scroll_enabled])
      attrs[:zoom]           = params[:zoom].to_f.positive? ? params[:zoom].to_f : 1.0
    when "immich"
      attrs[:external_id] = params[:external_id].to_s.strip
      # Default the name to the Immich album name if the user didn't type one
      if attrs[:name].blank? && attrs[:external_id].present? && ImmichClient.configured?
        album_data = ImmichClient.album(attrs[:external_id]) rescue nil
        attrs[:name] = album_data["albumName"] if album_data && album_data["albumName"].present?
      end
    end

    @new_source = Source.new(attrs)

    if @new_source.save
      # For Immich sources, kick off an immediate sync so the album is
      # available right away.
      if @new_source.immich?
        begin
          Indexer.sync_immich_source(@new_source)
        rescue => e
          Rails.logger.warn("Immich initial sync failed: #{e.class}: #{e.message}")
        end
      end

      announce_sources_changed
      redirect_to admin_sources_path, notice: "Added #{type} source “#{@new_source.name}”."
    else
      flash.now[:alert] = @new_source.errors.full_messages.join(", ")
      @sources = Source.left_joins(:images)
                       .select("sources.*, COUNT(images.id) AS image_count")
                       .group("sources.id").order(:name)
      render :sources, status: :unprocessable_entity
    end
  end

  # GET /admin/immich/albums — JSON list, used by the admin form.
  def immich_albums
    return render json: { error: "IMMICH_API_KEY is not set." }, status: :service_unavailable unless ImmichClient.configured?

    render json: { albums: ImmichClient.albums }
  rescue ImmichClient::AuthError => e
    render json: { error: e.message }, status: :unauthorized
  rescue ImmichClient::Error => e
    render json: { error: e.message }, status: :bad_gateway
  end

  def source_show
    @source      = Source.find(params[:id])
    @page, @per  = pagination
    @total       = @source.images.count
    @images      = @source.images.order(:position).offset((@page - 1) * @per).limit(@per)
    @total_pages = pages(@total, @per)
  end

  def destroy_source
    source = Source.find(params[:id])
    name   = source.name
    source.destroy
    announce_sources_changed
    redirect_to admin_sources_path, notice: "Deleted source “#{name}”."
  end

  def images
    @page, @per  = pagination
    @total       = Image.count
    @images      = Image.includes(:source)
                        .order("sources.name ASC, images.position ASC")
                        .joins(:source)
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
    s = SettingsStore.read
    @immich_base_url    = s["immich_base_url"].to_s
    @immich_api_key_set = s["immich_api_key"].present? || ENV["IMMICH_API_KEY"].present?
    @immich_api_key_src = if s["immich_api_key"].present?
                            "set in admin"
                          elsif ENV["IMMICH_API_KEY"].present?
                            "set via IMMICH_API_KEY env var"
                          else
                            "not set"
                          end
    @default_base_url   = ImmichClient::DEFAULT_BASE_URL
    @effective_base_url = ImmichClient.base_url
  end

  def update_settings
    updates = {}

    base_url = params[:immich_base_url].to_s.strip
    updates["immich_base_url"] = base_url.presence

    # Only overwrite the key if the user typed a new value into the input.
    new_key = params[:immich_api_key].to_s
    updates["immich_api_key"] = new_key if new_key.present?

    # An explicit "clear" checkbox lets the user remove the stored key.
    updates["immich_api_key"] = nil if params[:clear_immich_api_key] == "1"

    SettingsStore.write(updates)
    redirect_to admin_settings_path, notice: "Settings saved."
  end

  def screens
    @screens = Screen.includes(:current_image, screen_group: :selected_source).order(:code)
    @groups  = ScreenGroup.includes(:screens, :selected_source).order(:id)
  end

  def screens_json
    payload = Screen.includes(:current_image, screen_group: :selected_source).order(:code).map do |s|
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
          selected_source:   g.selected_source && { id: g.selected_source.id, name: g.selected_source.name, type: g.selected_source.source_type }
        },
        current_image: s.current_image && {
          id:       s.current_image.id,
          url:      s.current_image.url,
          filename: s.current_image.filename,
          source:   s.current_image.source.name
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

  def destroy_screen
    screen = Screen.find(params[:id])
    code   = screen.code
    group  = screen.screen_group
    screen.destroy
    group.destroy if group && group.screens.empty?
    announce_screens_changed
    redirect_to admin_screens_path, notice: "Screen #{code} deleted."
  end

  def groups
    @groups = ScreenGroup.includes(:screens, :selected_source).order(:id)
  end

  def destroy_group
    group  = ScreenGroup.find(params[:id])
    label  = group.display_name
    n      = group.screens.count
    group.screens.destroy_all
    group.destroy
    announce_screens_changed
    redirect_to admin_groups_path, notice: "Deleted group #{label} (#{n} screen#{'s' if n != 1})."
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

  def announce_sources_changed
    sources = Source.order(:name).pluck(:id, :name, :source_type, :url, :path).map do |id, name, type, url, path|
      { id: id, name: name, type: type, url: url, path: path }
    end
    ActionCable.server.broadcast("slideshow", {
      action:  "sources_changed",
      sources: sources
    })
  end
end
