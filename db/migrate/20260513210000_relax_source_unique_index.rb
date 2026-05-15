class RelaxSourceUniqueIndex < ActiveRecord::Migration[7.0]
  # The original (source_type, path) unique index was inherited from when
  # only Photos sources existed. Web and Immich sources use empty paths,
  # so the second one always collided. Restrict the uniqueness to photos
  # only, where path genuinely identifies the folder under slides/.
  #
  # Immich uniqueness is already enforced by the partial index on
  # (source_id, external_id) added with the Immich support migration.
  def up
    if index_exists?(:sources, [:source_type, :path], unique: true)
      remove_index :sources, column: [:source_type, :path]
    end
    add_index :sources, [:source_type, :path],
              unique: true,
              where:  "source_type = 'photos'",
              name:   "index_sources_on_photos_path"
  end

  def down
    remove_index :sources, name: "index_sources_on_photos_path" rescue nil
    add_index :sources, [:source_type, :path], unique: true
  end
end
