class CreateSettings < ActiveRecord::Migration[7.0]
  def change
    create_table :settings, id: false, primary_key: :key do |t|
      t.string :key,   null: false
      t.text   :value
      t.timestamps
    end
    add_index :settings, :key, unique: true
  end
end
