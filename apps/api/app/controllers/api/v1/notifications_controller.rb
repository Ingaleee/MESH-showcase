module Api
  module V1
    class NotificationsController < ApplicationController
      def index
        notifications = Notifications::Notification.where(account_id: current_account.id).order(created_at: :desc).limit(30)
        render json: { data: notifications.map { |row| row.attributes.slice("id", "title", "body", "resource_path", "read_at", "created_at") } }
      end

      def update
        notification = Notifications::Notification.where(account_id: current_account.id).find(params[:id])
        notification.update!(read_at: Time.current)
        head :no_content
      end
    end
  end
end
