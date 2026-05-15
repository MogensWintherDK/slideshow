class Image < ApplicationRecord
  belongs_to :source

  validates :filename, presence: true

  # Public URL the browser uses. The same path shape is used for both
  # photos and Immich sources — only the server-side serving differs.
  def url
    case source.source_type
    when "photos", "immich"
      "/slideshow/sources/#{source_id}/images/#{id}?v=#{updated_at.to_i}"
    else
      raise "Cannot serve image from #{source.source_type.inspect} source"
    end
  end

  # Filesystem path the controller reads from (photos sources only).
  def local_path
    raise "Not a photos image" unless source.photos?
    base = Image.slides_root
    base = base.join(source.path) if source.path.present?
    base.join(filename)
  end

  def self.slides_root
    Rails.root.join("slides")
  end
end
