Rails.application.routes.draw do
  root "slideshow#display"

  get  "/remote",          to: "remote#index",    as: :remote
  get  "/remote/settings", to: "remote#settings", as: :remote_settings
  post "/remote/command",  to: "remote#command",  as: :remote_command

  mount ActionCable.server => "/cable"
end
