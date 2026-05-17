class RemoveZoomFromSources < ActiveRecord::Migration[7.0]
  # Zoom is a screen concern, not a source concern. The display now
  # derives it from its own viewport via CSS, exactly like the timeline
  # uses clamp(…, vw, …) — small screens render natural, 4K screens
  # scale up automatically.
  def change
    remove_column :sources, :zoom, :float, null: false, default: 1.0
  end
end
