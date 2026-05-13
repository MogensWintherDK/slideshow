class CreateScreenGroups < ActiveRecord::Migration[7.0]
  # Move all per-screen playback state into ScreenGroup. Every screen
  # ends up in exactly one group. A standalone screen is just a group
  # of one. This is Sonos-style "rooms can be alone or grouped".
  def up
    create_table :screen_groups do |t|
      t.string  :name
      t.integer :selected_album_id
      t.string  :play_mode,     null: false, default: "linear"
      t.integer :delay_seconds, null: false, default: 5
      t.boolean :playing,       null: false, default: true
      t.timestamps
    end

    add_reference :screens, :screen_group, foreign_key: true

    # Backfill: each existing screen becomes its own group of one with
    # whatever settings were stored on the screen row.
    Screen.reset_column_information
    ScreenGroup.reset_column_information

    Screen.find_each do |s|
      group = ScreenGroup.create!(
        selected_album_id: s.read_attribute(:selected_album_id),
        play_mode:         s.read_attribute(:play_mode) || "linear",
        delay_seconds:     s.read_attribute(:delay_seconds) || 5,
        playing:           s.read_attribute(:playing).nil? ? true : s.read_attribute(:playing)
      )
      s.update_columns(screen_group_id: group.id)
    end

    remove_column :screens, :selected_album_id
    remove_column :screens, :play_mode
    remove_column :screens, :delay_seconds
    remove_column :screens, :playing
  end

  def down
    add_column :screens, :selected_album_id, :integer
    add_column :screens, :play_mode,         :string,  null: false, default: "linear"
    add_column :screens, :delay_seconds,     :integer, null: false, default: 5
    add_column :screens, :playing,           :boolean, null: false, default: true

    Screen.reset_column_information
    ScreenGroup.reset_column_information

    Screen.find_each do |s|
      group = ScreenGroup.find_by(id: s.screen_group_id) or next
      s.update_columns(
        selected_album_id: group.selected_album_id,
        play_mode:         group.play_mode,
        delay_seconds:     group.delay_seconds,
        playing:           group.playing
      )
    end

    remove_reference :screens, :screen_group, foreign_key: true
    drop_table :screen_groups
  end
end
