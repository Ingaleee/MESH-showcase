module Identity
  class Account < Platform::Record
    self.table_name = "identity_accounts"
    has_secure_password
    normalizes :email, with: ->(email) { email.strip.downcase }
    validates :email, presence: true, format: { with: /\A[^\s@]+@[^\s@]+\.[^\s@]+\z/ }, uniqueness: true
    validates :display_name, presence: true, length: { maximum: 80 }
    validates :password, length: { minimum: 12 }, if: -> { new_record? || password.present? }
    validates :persona, inclusion: { in: %w[client creator] }
  end
end
