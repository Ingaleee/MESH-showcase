class ApplicationController < ActionController::Base
  include Pundit::Authorization

  protect_from_forgery with: :exception
  prepend_before_action :preserve_session_on_read, if: -> { request.get? || request.head? }
  before_action :require_account!
  around_action :with_request_context

  rescue_from StandardError do |error|
    Rails.error.report(error, handled: true)
    render json: { code: "INTERNAL_ERROR", message: "Something went wrong. Retry with the same request key.", request_id: request.request_id }, status: :internal_server_error
  end
  rescue_from Platform::Error do |error|
    render json: { code: error.code, message: error.message, details: error.details, request_id: request.request_id }, status: error.status
  end
  rescue_from Pundit::NotAuthorizedError do
    render json: { code: "FORBIDDEN", message: "Access denied.", request_id: request.request_id }, status: :forbidden
  end
  rescue_from ActiveRecord::RecordNotFound do
    render json: { code: "NOT_FOUND", message: "Resource not found.", request_id: request.request_id }, status: :not_found
  end
  rescue_from ActiveRecord::RecordInvalid do |error|
    render json: {
      code: "VALIDATION_ERROR", message: "Check the supplied fields.",
      details: error.record.errors.to_hash, request_id: request.request_id
    }, status: :unprocessable_entity
  end
  rescue_from ActiveRecord::RecordNotUnique, ActiveRecord::StaleObjectError do
    render json: { code: "CONFLICT", message: "The resource has changed.", request_id: request.request_id }, status: :conflict
  end
  rescue_from ActionController::InvalidAuthenticityToken do
    render json: { code: "CSRF_INVALID", message: "Refresh the session and retry.", request_id: request.request_id }, status: :forbidden
  end
  rescue_from ActionController::ParameterMissing, ArgumentError, KeyError do
    render json: { code: "INVALID_INPUT", message: "Invalid request.", request_id: request.request_id }, status: :bad_request
  end
  rescue_from ActiveRecord::LockWaitTimeout, ActiveRecord::QueryCanceled do
    render json: { code: "RETRY_LATER", message: "The resource is busy. Retry with the same request key.", request_id: request.request_id }, status: :service_unavailable
  end
  rescue_from ActionController::TooManyRequests do
    render json: { code: "RATE_LIMITED", message: "Too many attempts. Try again later.", request_id: request.request_id }, status: :too_many_requests
  end

  private

  def preserve_session_on_read
    request.session_options[:skip] = true
  end

  def current_account
    return @current_account if defined?(@current_account)

    account = Identity::Account.find_by(id: session[:account_id])
    @current_account = account if account && session[:session_version] == account.session_version
  end

  def pundit_user
    current_account
  end

  def require_account!
    raise Platform::Error.new("UNAUTHENTICATED", "Sign in to continue.", status: 401) unless current_account
  end

  def require_operator!
    raise Platform::Error.new("FORBIDDEN", "Operator access required.", status: 403) unless current_account&.operator?
  end

  def idempotency_key
    request.headers["Idempotency-Key"]
  end

  def with_request_context
    Platform::Current.set(actor_id: current_account&.id, correlation_id: request.request_id) { yield }
  end
end
