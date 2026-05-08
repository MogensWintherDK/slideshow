class RemoteController < ApplicationController
  layout false
  skip_before_action :verify_authenticity_token, only: :command

  def index
    @settings = SettingsStore.read
  end

  # Returns current settings as JSON (used by the remote on load).
  def settings
    render json: SettingsStore.read
  end

  def command
    name    = params[:action_name].to_s
    payload = { action: name }

    case name
    when "play", "pause", "reset"
      # nothing extra to add
    when "set_delay"
      delay = params[:delay].to_i
      delay = 5 if delay < 1
      payload[:delay] = delay
    when "set_birthday_mode"
      enabled = ActiveModel::Type::Boolean.new.cast(params[:enabled])
      SettingsStore.write("birthday_mode" => enabled)
      payload[:enabled] = enabled
    when "set_birthday"
      raw      = params[:birthday].to_s
      birthday = raw.empty? ? nil : raw
      SettingsStore.write("birthday" => birthday)
      payload[:birthday] = birthday
    else
      return head :bad_request
    end

    ActionCable.server.broadcast("slideshow", payload)
    head :ok
  end
end
