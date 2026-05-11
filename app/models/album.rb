class Album < ApplicationRecord
  has_many :images, -> { order(:position) }, dependent: :destroy

  validates :name,       presence: true
  validates :album_type, presence: true, inclusion: { in: %w[local immich] }
  validates :path,       uniqueness: { scope: :album_type }

  scope :local, -> { where(album_type: "local") }
end
