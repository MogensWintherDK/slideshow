class Source < ApplicationRecord
  TYPES = %w[photos web immich].freeze

  has_many :images, -> { order(:position) }, dependent: :destroy

  validates :name,        presence: true
  validates :source_type, presence: true, inclusion: { in: TYPES }
  validate  :path_unique_within_photos
  validate  :url_required_for_web
  validate  :external_id_required_for_immich

  scope :photos, -> { where(source_type: "photos") }
  scope :web,    -> { where(source_type: "web") }
  scope :immich, -> { where(source_type: "immich") }

  def photos?; source_type == "photos"; end
  def web?;    source_type == "web";    end
  def immich?; source_type == "immich"; end

  def slides_dir
    return nil unless photos?
    base = Image.slides_root
    path.present? ? base.join(path) : base
  end

  private

  def path_unique_within_photos
    return unless photos?
    scope = Source.where(source_type: "photos", path: path.to_s)
    scope = scope.where.not(id: id) if persisted?
    errors.add(:path, "is already used by another photos source") if scope.exists?
  end

  def url_required_for_web
    errors.add(:url, "is required for web sources") if web? && url.blank?
  end

  def external_id_required_for_immich
    errors.add(:external_id, "(Immich album) must be selected") if immich? && external_id.blank?
  end
end
