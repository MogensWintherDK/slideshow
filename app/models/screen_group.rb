class ScreenGroup < ApplicationRecord
  has_many :screens
  belongs_to :selected_album, class_name: "Album", optional: true,
                              foreign_key: :selected_album_id

  validates :play_mode, inclusion: { in: %w[linear random] }

  # If the user set a name use it. Otherwise compose one from the
  # member screens' codes (or "(empty)" if there are none).
  def display_name
    return name if name.present?
    codes = screens.order(:code).pluck(:code)
    return "(empty)" if codes.empty?
    return codes.first if codes.size == 1
    codes.join(" + ")
  end

  # JSON serialization shared by the remote and admin.
  def to_remote_json
    {
      id:                 id,
      name:               name,
      display_name:       display_name,
      selected_album_id:  selected_album_id,
      play_mode:          play_mode,
      delay_seconds:      delay_seconds,
      playing:            playing,
      birthday_mode:      birthday_mode,
      birthday:           birthday,
      screen_ids:         screens.pluck(:id),
      screens:            screens.includes(:current_image).order(:code).map(&:to_remote_json)
    }
  end
end
