module Publishing
  class Validation < Platform::Record
    self.table_name = "publishing_validations"
    belongs_to :candidate, class_name: "Publishing::Candidate"
  end
end
