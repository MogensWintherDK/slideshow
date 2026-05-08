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
       .map { |name| build_image_data(images_path.join(name), name) }
  rescue Errno::ENOENT
    []
  end

  def build_image_data(path, name)
    info         = read_exif(path)
    location_key = nil
    location     = nil

    if info[:lat] && info[:lon]
      location_key = Geocoder.key_for(info[:lat], info[:lon])
      location     = Geocoder.lookup(info[:lat], info[:lon])
      Geocoder.resolve_async(info[:lat], info[:lon]) if location.nil?
    end

    {
      url:          "/slides/#{name}",
      date:         info[:date]&.iso8601,
      location_key: location_key,
      location:     location
    }
  end

  # EXIF DateTimeOriginal + GPS, with mtime fallback for the date.
  def read_exif(path)
    exif = EXIFR::JPEG.new(path.to_s)
    date = exif.date_time_original || File.mtime(path)
    gps  = exif.gps
    { date: date, lat: gps&.latitude, lon: gps&.longitude }
  rescue StandardError
    { date: (File.mtime(path) rescue nil), lat: nil, lon: nil }
  end
end
