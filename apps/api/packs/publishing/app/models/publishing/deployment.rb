module Publishing
  class Deployment < Platform::Record
    self.table_name = "publishing_deployments"
    belongs_to :partner, class_name: "Publishing::Partner"
    belongs_to :candidate, class_name: "Publishing::Candidate"
    belongs_to :validation, class_name: "Publishing::Validation"
    belongs_to :rollback_of, class_name: "Publishing::Deployment", optional: true
  end
end
