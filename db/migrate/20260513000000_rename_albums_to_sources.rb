class RenameAlbumsToSources < ActiveRecord::Migration[7.0]
  # albums → sources, with album_type → source_type. A "source" now has
  # a type ("photos" or "web"); web sources hold a URL instead of a path.
  def up
    rename_table :albums, :sources
    rename_column :sources, :album_type, :source_type
    add_column :sources, :url, :string

    rename_column :images, :album_id, :source_id
    rename_column :screen_groups, :selected_album_id, :selected_source_id

    src = Class.new(ActiveRecord::Base)
    src.table_name = "sources"
    src.where(source_type: "local").update_all(source_type: "photos")
  end

  def down
    src = Class.new(ActiveRecord::Base)
    src.table_name = "sources"
    src.where(source_type: "photos").update_all(source_type: "local")

    rename_column :screen_groups, :selected_source_id, :selected_album_id
    rename_column :images,        :source_id,          :album_id

    remove_column :sources, :url
    rename_column :sources, :source_type, :album_type
    rename_table  :sources, :albums
  end
end
