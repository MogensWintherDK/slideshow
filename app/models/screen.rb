require "securerandom"

class Screen < ApplicationRecord
  belongs_to :screen_group
  belongs_to :current_image, class_name: "Image", optional: true

  before_validation :ensure_code_and_token, on: :create
  before_validation :ensure_group,          on: :create

  validates :code,         presence: true, uniqueness: true
  validates :cookie_token, presence: true, uniqueness: true

  # Human-friendly label.
  def display_name
    nickname.presence || code
  end

  # JSON used by remote and admin.
  def to_remote_json
    {
      id:                id,
      code:              code,
      nickname:          nickname,
      display_name:      display_name,
      last_seen_at:      last_seen_at&.iso8601,
      screen_group_id:   screen_group_id,
      current_image_id:  current_image_id,
      current_image_url: current_image&.url
    }
  end

  # Move this screen into another group. If the source group ends up
  # empty afterwards, delete it so we don't accumulate ghost groups.
  def move_to_group!(target_group)
    return if screen_group_id == target_group.id
    source = screen_group
    update!(screen_group_id: target_group.id)
    source.destroy if source && source.screens.empty?
  end

  # Move this screen into a brand new (empty) group with fresh defaults.
  # Useful for "ungroup".
  def split_into_new_group!
    return if screen_group.screens.count == 1   # already alone
    fresh = ScreenGroup.create!
    move_to_group!(fresh)
    fresh
  end

  def self.generate_unique_code
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".chars
    20.times do
      code = 4.times.map { alphabet.sample }.join
      return code unless exists?(code: code)
    end
    raise "Could not allocate a unique screen code after 20 attempts"
  end

  private

  def ensure_code_and_token
    self.code         ||= self.class.generate_unique_code
    self.cookie_token ||= SecureRandom.hex(16)
  end

  def ensure_group
    self.screen_group ||= ScreenGroup.create!
  end
end
