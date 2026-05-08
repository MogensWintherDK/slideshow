class SlideshowChannel < ApplicationCable::Channel
  def subscribed
    stream_from "slideshow"
  end

  def unsubscribed
  end
end
