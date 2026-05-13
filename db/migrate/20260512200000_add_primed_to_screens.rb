class AddPrimedToScreens < ActiveRecord::Migration[7.0]
  # A screen is "primed" once a remote has explicitly targeted it. Until
  # then the display sits on the Chromecast-style splash and waits.
  #
  # All screens that already exist when this migration runs were behaving
  # under the old auto-start rules, so we backfill them to primed = true
  # to keep them running through the upgrade.
  def up
    add_column :screens, :primed, :boolean, null: false, default: false
    Screen.reset_column_information
    Screen.update_all(primed: true)
  end

  def down
    remove_column :screens, :primed
  end
end
