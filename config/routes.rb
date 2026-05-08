Rails.application.routes.draw do
  root "slideshow#display"

  get  "/remote",        to: "remote#index",   as: :remote
  post "/remote/command", to: "remote#command", as: :remote_command

  mount ActionCable.server => "/cable"
end
