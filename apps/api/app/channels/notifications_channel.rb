class NotificationsChannel < ApplicationCable::Channel
  def subscribed
    stream_from "notifications:#{current_account.id}"
  end
end
