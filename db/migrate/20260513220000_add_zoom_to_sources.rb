class AddZoomToSources < ActiveRecord::Migration[7.0]
  # Web sources can specify a zoom factor (e.g. 1.5, 2.0) so a desktop-
  # sized page fills a 4K kiosk display. 1.0 = no zoom.
  def change
    add_column :sources, :zoom, :float, null: false, default: 1.0
  end
end
