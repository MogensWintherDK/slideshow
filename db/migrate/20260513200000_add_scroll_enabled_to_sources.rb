class AddScrollEnabledToSources < ActiveRecord::Migration[7.0]
  # Web sources opt-in to being served via our same-origin proxy so
  # the parent page can scroll the iframe content. Default off so new
  # sources keep the simplest "embed the URL directly" behaviour.
  def change
    add_column :sources, :scroll_enabled, :boolean, null: false, default: false
  end
end
