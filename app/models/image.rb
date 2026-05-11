class Image < ApplicationRecord
  belongs_to :album

  validates :filename, presence: true,
                       uniqueness: { scope: :album_id, case_sensitive: false }

  # Public URL the browser uses. Goes through Rails so we can set proper
  # cache headers and so files don't sit in public/. The ?v= parameter
  # is the updated_at timestamp — when an image record is touched (e.g.
  # re-indexed because the file changed) the URL changes and the browser
  # refetches; otherwise it keeps the cached bytes for up to a year.
  def url
    case album.album_type
    when "local"
      "/slideshow/albums/#{album_id}/images/#{id}?v=#{updated_at.to_i}"
    else
      raise "Unknown album_type: #{album.album_type.inspect}"
    end
  end

  # Filesystem path the controller reads from. Local-album only.
  def local_path
    raise "Not a local image" unless album.album_type == "local"
    base = Image.slides_root
    base = base.join(album.path) if album.path.present?
    base.join(filename)
  end

  # Root folder for local photos. Lives at the project root (not in
  # public/) so files are never served directly by the static handler.
  def self.slides_root
    Rails.root.join("slides")
  end
end
