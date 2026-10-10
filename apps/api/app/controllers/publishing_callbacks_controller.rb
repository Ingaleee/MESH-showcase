# Machine callbacks authenticate the raw payload with HMAC; browser cookies are not authority.
class PublishingCallbacksController < ActionController::API
  def create
    raise Platform::Error.new("PUBLISHING_DISABLED", "Publishing is disabled.", status: 503) unless ENV.fetch("MESH_PUBLISHING_ENABLED", "false") == "true"
    partner = Publishing::Partner.find(params[:partner_id])
    result = Publishing::ReceiveCallback.call(
      partner: partner, event_id: request.headers["X-Event-ID"], timestamp: request.headers["X-Callback-Timestamp"],
      signature: request.headers["X-Callback-Signature"], bytes: request.raw_post
    )
    render json: result
  rescue Platform::Error => error
    render json: { code: error.code, message: error.message, request_id: request.request_id }, status: error.status
  rescue ActiveRecord::RecordNotUnique
    render json: { code: "PARTNER_SEQUENCE_CONFLICT", message: "Remote sequence belongs to another operation." }, status: :conflict
  rescue ActiveRecord::RecordNotFound
    render json: { code: "NOT_FOUND" }, status: :not_found
  end
end
