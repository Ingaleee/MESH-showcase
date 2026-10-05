module Engagements
  class Submission < Platform::Record
    self.table_name = "engagements_submissions"
    has_many :work_files, class_name: "Engagements::WorkFile"
    validates :content, presence: true, length: { maximum: 20000 }
    validates :title, length: { maximum: 160 }
  end
end
