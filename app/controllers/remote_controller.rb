class RemoteController < ApplicationController
  layout false
  skip_before_action :verify_authenticity_token, only: :command

  def index
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
    else
      return head :bad_request
    end

    ActionCable.server.broadcast("slideshow", payload)
    head :ok
  end
end
