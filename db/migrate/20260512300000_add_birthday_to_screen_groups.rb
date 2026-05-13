class AddBirthdayToScreenGroups < ActiveRecord::Migration[7.0]
  # Birthday mode is now a per-group setting (it really only makes sense
  # at the album scope a group is showing). Anything currently in the
  # global SettingsStore is backfilled onto every existing group so the
  # upgrade is seamless.
  def up
    add_column :screen_groups, :birthday_mode, :boolean, null: false, default: false
    add_column :screen_groups, :birthday,      :string

    ScreenGroup.reset_column_information

    global = SettingsStore.read rescue {}
    if global["birthday_mode"] || global["birthday"].present?
      ScreenGroup.update_all(
        birthday_mode: !!global["birthday_mode"],
        birthday:      global["birthday"]
      )
    end
  end

  def down
    remove_column :screen_groups, :birthday_mode
    remove_column :screen_groups, :birthday
  end
end
