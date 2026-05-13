# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.0].define(version: 2026_05_12_300000) do
  create_table "albums", force: :cascade do |t|
    t.string "name", null: false
    t.string "album_type", default: "local", null: false
    t.string "path", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["album_type", "path"], name: "index_albums_on_album_type_and_path", unique: true
  end

  create_table "images", force: :cascade do |t|
    t.integer "album_id", null: false
    t.string "filename", null: false
    t.datetime "taken_at"
    t.float "latitude"
    t.float "longitude"
    t.string "location_key"
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["album_id", "filename"], name: "index_images_on_album_id_and_filename", unique: true
    t.index ["album_id", "position"], name: "index_images_on_album_id_and_position"
    t.index ["album_id"], name: "index_images_on_album_id"
    t.index ["location_key"], name: "index_images_on_location_key"
  end

  create_table "locations", id: false, force: :cascade do |t|
    t.string "key", null: false
    t.string "country"
    t.string "area"
    t.datetime "resolved_at", null: false
    t.index ["key"], name: "index_locations_on_key", unique: true
  end

  create_table "screen_groups", force: :cascade do |t|
    t.string "name"
    t.integer "selected_album_id"
    t.string "play_mode", default: "linear", null: false
    t.integer "delay_seconds", default: 5, null: false
    t.boolean "playing", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "birthday_mode", default: false, null: false
    t.string "birthday"
  end

  create_table "screens", force: :cascade do |t|
    t.string "code", null: false
    t.string "cookie_token", null: false
    t.string "nickname"
    t.datetime "last_seen_at"
    t.integer "current_image_id"
    t.integer "current_position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "screen_group_id"
    t.boolean "primed", default: false, null: false
    t.index ["code"], name: "index_screens_on_code", unique: true
    t.index ["cookie_token"], name: "index_screens_on_cookie_token", unique: true
    t.index ["screen_group_id"], name: "index_screens_on_screen_group_id"
  end

  create_table "settings", id: false, force: :cascade do |t|
    t.string "key", null: false
    t.text "value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_settings_on_key", unique: true
  end

  add_foreign_key "images", "albums", on_delete: :cascade
  add_foreign_key "screens", "screen_groups"
end
