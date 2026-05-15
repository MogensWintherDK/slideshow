class AddImmichSupport < ActiveRecord::Migration[7.0]
  def change
    add_column :sources, :external_id, :string   # Immich album UUID
    add_column :images,  :external_id, :string   # Immich asset UUID

    # An Immich album UUID identifies the source uniquely
    add_index :sources, :external_id, unique: true, where: "external_id IS NOT NULL"

    # Within one Immich source, each asset UUID is unique
    add_index :images, [:source_id, :external_id], unique: true, where: "external_id IS NOT NULL"
  end
end
