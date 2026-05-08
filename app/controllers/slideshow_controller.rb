class SlideshowController < ApplicationController
  layout false

  def display
    @images = load_images
  end

  private

  def load_images
    images_path = Rails.root.join("public", "slides")
    Dir.children(images_path)
       .select { |name| name =~ /\.jpe?g\z/i }
       .sort
       .map { |name| "/slides/#{name}" }
  rescue Errno::ENOENT
    []
  end
end
