class RemoteController < ApplicationController
  layout false
  skip_before_action :verify_authenticity_token, only: :command

  def index
    @settings = SettingsStore.read
    @albums   = Album.order(:name).pluck(:id, :name, :album_type).map { |id, name, type| { id: id, name: name, type: type } }
    @screens  = Screen.includes(:current_image).order(:code).map(&:to_remote_json)
    @groups   = ScreenGroup.includes(:screens).order(:id).map(&:to_remote_json)
  end

  # JSON snapshot used by the remote when (re)connecting.
  def settings
    render json: {
      settings: SettingsStore.read,
      albums:   Album.order(:name).pluck(:id, :name, :album_type).map { |id, name, type| { id: id, name: name, type: type } },
      screens:  Screen.includes(:current_image).order(:code).map(&:to_remote_json),
      groups:   ScreenGroup.includes(:screens).order(:id).map(&:to_remote_json)
    }
  end

  def command
    name = params[:action_name].to_s

    raw_target_group = params[:target_group_id].to_s
    target_group = nil
    if raw_target_group.present?
      target_group = ScreenGroup.find_by(id: raw_target_group)
      return head :bad_request unless target_group
    end

    case name
    # ── Pure playback (no DB state change) ────────────────────────────────
    when "reset"
      broadcast_playback(target_group, action: "reset")
    when "skip"
      broadcast_playback(target_group, action: "skip", delta: params[:delta].to_i)

    # ── Stateful playback (write to group, then broadcast) ───────────────
    when "play"
      apply_to_groups(target_group) { |g| g.update_columns(playing: true) }
      broadcast_playback(target_group, action: "play")
    when "pause"
      apply_to_groups(target_group) { |g| g.update_columns(playing: false) }
      broadcast_playback(target_group, action: "pause")
    when "set_delay"
      delay = params[:delay].to_i.clamp(1, 3600)
      apply_to_groups(target_group) { |g| g.update_columns(delay_seconds: delay) }
      broadcast_playback(target_group, action: "set_delay", delay: delay)
    when "set_play_mode"
      mode = params[:mode].to_s
      mode = "linear" unless %w[linear random].include?(mode)
      apply_to_groups(target_group) { |g| g.update_columns(play_mode: mode) }
      broadcast_playback(target_group, action: "set_play_mode", mode: mode)
    when "set_album"
      raw       = params[:album_id].to_s
      album_id  = raw.empty? ? nil : raw.to_i
      return head :bad_request if album_id && !Album.exists?(id: album_id)
      apply_to_groups(target_group) { |g| g.update_columns(selected_album_id: album_id) }
      broadcast_playback(target_group, action: "set_album", album_id: album_id)

    # ── Per-group birthday timeline ──────────────────────────────────────
    when "set_birthday_mode"
      enabled = ActiveModel::Type::Boolean.new.cast(params[:enabled])
      apply_to_groups(target_group) { |g| g.update_columns(birthday_mode: enabled) }
      broadcast_playback(target_group, action: "set_birthday_mode", enabled: enabled)
    when "set_birthday"
      raw      = params[:birthday].to_s
      birthday = raw.empty? ? nil : raw
      apply_to_groups(target_group) { |g| g.update_columns(birthday: birthday) }
      broadcast_playback(target_group, action: "set_birthday", birthday: birthday)

    # ── Group management ─────────────────────────────────────────────────
    when "add_screens_to_group"
      return head :bad_request unless target_group
      ids = Array(params[:screen_ids]).map(&:to_i)
      Screen.where(id: ids).find_each { |s| s.move_to_group!(target_group) }
      # Adding a screen to a group is an explicit user action targeting it,
      # so we treat it like a wake-up too.
      Screen.where(id: ids).update_all(primed: true)
      ActionCable.server.broadcast("slideshow", {
        action: "wake", target_screen_ids: ids
      })
      announce_groups
    when "remove_screen_from_group"
      sid = params[:screen_id].to_i
      s = Screen.find_by(id: sid)
      return head :bad_request unless s
      s.split_into_new_group!
      announce_groups
    when "rename_group"
      return head :bad_request unless target_group
      new_name = params[:name].to_s.strip.presence
      target_group.update_columns(name: new_name)
      announce_groups
    when "delete_empty_groups"
      ScreenGroup.left_joins(:screens).where(screens: { id: nil }).destroy_all
      announce_groups

    else
      return head :bad_request
    end

    head :ok
  end

  private

  def apply_to_groups(target_group)
    if target_group
      yield target_group
    else
      ScreenGroup.find_each { |g| yield g }
    end
  end

  # Broadcast a playback action with a resolved target_screen_ids list
  # (nil = every screen everywhere). Also marks the targeted screens as
  # "primed" — once a remote has spoken to a screen it's no longer in
  # the wait-for-cast splash and will auto-resume on subsequent reloads.
  def broadcast_playback(target_group, payload)
    screen_ids = target_group ? target_group.screens.pluck(:id) : nil
    Screen.where(id: screen_ids).where(primed: false).update_all(primed: true) if screen_ids
    ActionCable.server.broadcast("slideshow",
      payload.merge(target_screen_ids: screen_ids))
  end

  def announce_groups
    ActionCable.server.broadcast("slideshow", {
      action:  "screens_changed",
      screens: Screen.includes(:current_image).order(:code).map(&:to_remote_json),
      groups:  ScreenGroup.includes(:screens).order(:id).map(&:to_remote_json)
    })
  end
end
