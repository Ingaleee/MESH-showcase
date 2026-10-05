require "openssl"
module Api
  module V1
    class WebhooksController < ApplicationController
      skip_before_action :require_account!
      skip_before_action :verify_authenticity_token

      def create
        body = request.raw_post
        timestamp = request.headers["X-Mesh-Timestamp"].to_s
        signature = request.headers["X-Mesh-Signature"].to_s
        expected = OpenSSL::HMAC.hexdigest("SHA256", ENV.fetch("MESH_WEBHOOK_SECRET"), "#{timestamp}.#{body}")
        fresh = timestamp.match?(/\A\d+\z/) && (Time.current.to_i - timestamp.to_i).abs <= 300
        unless fresh && ActiveSupport::SecurityUtils.secure_compare(signature, expected)
          raise Platform::Error.new("INVALID_SIGNATURE", "Invalid webhook signature.", status: 401)
        end
        payload = JSON.parse(body)
        event_id = payload.fetch("event_id")
        operation_id = payload.fetch("operation_id")
        unless event_id.is_a?(String) && event_id.bytesize <= 200 && operation_id.to_s.match?(/\A[0-9a-f-]{36}\z/)
          raise Platform::Error.new("INVALID_WEBHOOK", "Invalid event.", status: 400)
        end
        Finance::WebhookReceipt.create_or_find_by!(provider_event_id: event_id) do |row|
          row.payload = { operation_id: operation_id }
        end
        render json: { received: true }
      rescue JSON::ParserError, KeyError
        raise Platform::Error.new("INVALID_WEBHOOK", "Invalid event.", status: 400)
      end
    end
  end
end
