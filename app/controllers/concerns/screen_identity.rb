# Resolves (and creates if needed) the Screen for the current request based
# on a signed cookie. The cookie persists for 5 years; as long as the browser
# keeps it, the same browser keeps its identity (code, nickname, group, etc.).
module ScreenIdentity
  extend ActiveSupport::Concern

  COOKIE_NAME = :screen_token
  COOKIE_TTL  = 5.years

  included do
    helper_method :current_screen
  end

  private

  def current_screen
    @current_screen ||= find_or_create_screen
  end

  def find_or_create_screen
    token = cookies.signed[COOKIE_NAME]
    screen = Screen.find_by(cookie_token: token) if token.present?

    unless screen
      screen = Screen.create!
      cookies.signed[COOKIE_NAME] = {
        value:    screen.cookie_token,
        expires:  COOKIE_TTL.from_now,
        httponly: true,
        same_site: :lax
      }
      ScreenIdentity.broadcast_screens_changed
    end

    screen.update_columns(last_seen_at: Time.current) if screen.persisted?
    screen
  end

  # Push the latest screens + groups so the remote re-renders.
  def self.broadcast_screens_changed
    ActionCable.server.broadcast("slideshow", {
      action:  "screens_changed",
      screens: Screen.includes(:current_image).order(:code).map(&:to_remote_json),
      groups:  ScreenGroup.includes(:screens).order(:id).map(&:to_remote_json)
    })
  end
end
