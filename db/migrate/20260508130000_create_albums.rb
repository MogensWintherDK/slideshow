class CreateAlbums < ActiveRecord::Migration[7.0]
  def change
    create_table :albums do |t|
      t.string :name,       null: false
      t.string :album_type, null: false, default: "local"
      t.string :path,       null: false, default: ""
      t.timestamps
    end

    # A local album is uniquely identified by its on-disk path; we leave
    # room for other types (Immich, etc.) to enforce their own constraints.
    add_index :albums, [:album_type, :path], unique: true
  end
end
