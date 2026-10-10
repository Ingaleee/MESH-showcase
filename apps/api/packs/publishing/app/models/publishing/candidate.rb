module Publishing
  class Candidate < Platform::Record
    self.table_name = "publishing_candidates"
    belongs_to :partner, class_name: "Publishing::Partner"
    belongs_to :artifact_blob, class_name: "ActiveStorage::Blob"
    has_many :validations, class_name: "Publishing::Validation"
    has_many :deployments, class_name: "Publishing::Deployment"
  end
end
