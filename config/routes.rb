Rails.application.routes.draw do
  root "slideshow#display"

  get  "/slideshow/playlist", to: "slideshow#playlist", as: :slideshow_playlist
  get  "/slideshow/timeline", to: "slideshow#timeline", as: :slideshow_timeline
  get  "/slideshow/albums/:album_id/images/:image_id",
       to: "slideshow#image", as: :slideshow_image
  post "/screen/state",       to: "slideshow#update_state", as: :screen_state

  get  "/remote",          to: "remote#index",    as: :remote
  get  "/remote/settings", to: "remote#settings", as: :remote_settings
  post "/remote/command",  to: "remote#command",  as: :remote_command

  # Admin (no auth — local network only)
  get  "/admin",                to: "admin#index",         as: :admin
  get  "/admin/albums",         to: "admin#albums",        as: :admin_albums
  get  "/admin/albums/:id",     to: "admin#album_show",    as: :admin_album
  get  "/admin/images",         to: "admin#images",        as: :admin_images
  get  "/admin/locations",      to: "admin#locations",     as: :admin_locations
  get  "/admin/settings",       to: "admin#settings",      as: :admin_settings
  get  "/admin/screens",        to: "admin#screens",       as: :admin_screens
  get  "/admin/screens.json",   to: "admin#screens_json"
  get  "/admin/groups",         to: "admin#groups",        as: :admin_groups
  patch  "/admin/screens/:id",  to: "admin#update_screen",  as: :admin_screen
  delete "/admin/screens/:id",  to: "admin#destroy_screen"
  delete "/admin/groups/:id",   to: "admin#destroy_group",  as: :destroy_admin_group
  post   "/admin/reindex",      to: "admin#reindex",        as: :admin_reindex

  mount ActionCable.server => "/cable"
end
