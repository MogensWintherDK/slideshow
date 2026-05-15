class ScreenGroup < ApplicationRecord
  has_many :screens
  belongs_to :selected_source, class_name: "Source", optional: true,
                               foreign_key: :selected_source_id

  validates :play_mode, inclusion: { in: %w[linear random] }

  def display_name
    return name if name.present?
    codes = screens.order(:code).pluck(:code)
    return "(empty)" if codes.empty?
    return codes.first if codes.size == 1
    codes.join(" + ")
  end

  def to_remote_json
    {
      id:                 id,
      name:               name,
      display_name:       display_name,
      selected_source_id: selected_source_id,
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
