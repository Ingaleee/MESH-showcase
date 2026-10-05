module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_account

    def connect
      session = request.session
      account = Identity::Account.find_by(id: session[:account_id])
      unless account && session[:session_version] == account.session_version
        reject_unauthorized_connection
      end
      self.current_account = account
    end
  end
end
