class Image < ApplicationRecord
  belongs_to :album

  validates :filename, presence: true,
                       uniqueness: { scope: :album_id, case_sensitive: false }

  # Public URL the browser fetches the JPEG from.
  # For local albums we serve files straight out of public/slides/.
  def url
    case album.album_type
    when "local"
      parts = ["/slides"]
      parts << album.path if album.path.present?
      parts << filename
      parts.join("/")
    else
      raise "Unknown album_type: #{album.album_type.inspect}"
    end
  end
end
