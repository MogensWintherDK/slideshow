class CreateScreens < ActiveRecord::Migration[7.0]
  def change
    create_table :screens do |t|
      t.string  :code,             null: false              # 4-char like "AB3F"
      t.string  :cookie_token,     null: false              # opaque token in cookie
      t.string  :nickname                                   # user-set label
      t.datetime :last_seen_at

      # What's currently on the screen (for the admin live preview)
      t.integer :current_image_id
      t.integer :current_position

      # Per-screen control state. Defaults mirror SettingsStore::DEFAULTS
      # so a brand-new screen behaves the same as today.
      t.integer :selected_album_id
      t.string  :play_mode,        null: false, default: "linear"
      t.integer :delay_seconds,    null: false, default: 5
      t.boolean :playing,          null: false, default: true

      t.timestamps
    end
    add_index :screens, :code,         unique: true
    add_index :screens, :cookie_token, unique: true
  end
end
