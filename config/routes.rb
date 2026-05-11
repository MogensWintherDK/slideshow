Rails.application.routes.draw do
  root "slideshow#display"

  get  "/slideshow/playlist", to: "slideshow#playlist", as: :slideshow_playlist
  get  "/slideshow/timeline", to: "slideshow#timeline", as: :slideshow_timeline

  get  "/remote",          to: "remote#index",    as: :remote
  get  "/remote/settings", to: "remote#settings", as: :remote_settings
  post "/remote/command",  to: "remote#command",  as: :remote_command

  mount ActionCable.server => "/cable"
end
