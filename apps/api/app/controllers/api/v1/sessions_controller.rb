module Api
  module V1
    class SessionsController < ApplicationController
      skip_before_action :preserve_session_on_read, only: :show
      skip_before_action :require_account!, only: %i[show create register]
      before_action :throttle_authentication, only: %i[create register]

      def show
        render json: { account: Presenters.account(current_account, private_fields: true), csrf_token: form_authenticity_token }
      end

      def create
        input = params.require(:session).permit(:email, :password)
        account = Identity::Account.find_by(email: input[:email].to_s.strip.downcase)
        unless account&.authenticate(input[:password].to_s)
          BCrypt::Password.create("timing-padding", cost: BCrypt::Engine.cost) unless account
          raise Platform::Error.new("INVALID_CREDENTIALS", "Email or password is incorrect.", status: 401)
        end
        establish_session(account)
      end

      def register
        account = Identity::Account.create!(params.require(:account).permit(:email, :display_name, :password, :persona))
        establish_session(account)
      end

      def destroy
        current_account.increment!(:session_version)
        ActionCable.server.remote_connections.where(current_account: current_account).disconnect
        reset_session
        render json: { account: nil, csrf_token: form_authenticity_token }
      end

      private

      def throttle_authentication
        decision = Platform::RateLimiter.consume(scope: "authentication", identity: request.remote_ip, limit: 15, period: 3.minutes)
        return if decision.allowed

        response.headers["Retry-After"] = decision.retry_after.to_s
        raise ActionController::TooManyRequests
      end

      def establish_session(account)
        reset_session
        session[:account_id] = account.id
        session[:session_version] = account.session_version
        render json: { account: Presenters.account(account, private_fields: true), csrf_token: form_authenticity_token }
      end
    end
  end
end
