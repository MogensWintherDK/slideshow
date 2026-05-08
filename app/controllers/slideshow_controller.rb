require "exifr/jpeg"

class SlideshowController < ApplicationController
  layout false

  def display
    @images   = load_images
    @settings = SettingsStore.read
  end

  private

  def load_images
    images_path = Rails.root.join("public", "slides")
    Dir.children(images_path)
       .select { |name| name =~ /\.jpe?g\z/i }
       .sort
       .map do |name|
         path = images_path.join(name)
         { url:  "/slides/#{name}",
           date: image_date(path)&.iso8601 }
       end
  rescue Errno::ENOENT
    []
  end

  # Prefer EXIF DateTimeOriginal (when the photo was taken).
  # Fall back to file mtime if EXIF is missing or malformed.
  def image_date(path)
    EXIFR::JPEG.new(path.to_s).date_time_original || File.mtime(path)
  rescue StandardError
    File.mtime(path) rescue nil
  end
end
