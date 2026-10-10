module Publishing
  class Partner < Platform::Record
    self.table_name = "publishing_partners"
    belongs_to :owner, class_name: "Identity::Account"
    has_many :candidates, class_name: "Publishing::Candidate", foreign_key: :partner_id
    has_many :deployments, class_name: "Publishing::Deployment", foreign_key: :partner_id
    belongs_to :active_deployment, class_name: "Publishing::Deployment", optional: true
    validates :name, length: { in: 1..80 }
    validates :credential_ref, format: { with: /\A[A-Z][A-Z0-9_]{0,40}\z/ }
    validates :contract_version, inclusion: { in: [ "1" ] }
  end
end
