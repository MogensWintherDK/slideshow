class CreateLocations < ActiveRecord::Migration[7.0]
  def change
    create_table :locations, id: false, primary_key: :key do |t|
      t.string   :key,     null: false
      t.string   :country
      t.string   :area
      t.datetime :resolved_at, null: false
    end
    add_index :locations, :key, unique: true
  end
end
