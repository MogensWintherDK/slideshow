class CreateImages < ActiveRecord::Migration[7.0]
  def change
    create_table :images do |t|
      t.belongs_to :album, null: false, foreign_key: { on_delete: :cascade }
      t.string   :filename,     null: false
      t.datetime :taken_at
      t.float    :latitude
      t.float    :longitude
      t.string   :location_key
      t.integer  :position,     null: false, default: 0
      t.timestamps
    end

    add_index :images, [:album_id, :filename], unique: true
    add_index :images, [:album_id, :position]
    add_index :images, :location_key
  end
end
