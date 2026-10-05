module Engagements
  class WorkFile < Platform::Record
    self.table_name = "engagements_work_files"
    belongs_to :engagement, class_name: "Engagements::Engagement"
    belongs_to :creator, class_name: "Identity::Account"
    belongs_to :submission, class_name: "Engagements::Submission", optional: true
    has_one_attached :file

    def visible_to?(actor)
      actor && (creator_id == actor.id || (submission_id.present? && engagement.client_id == actor.id))
    end

    def manifest
      { "id" => id, "filename" => file.filename.to_s, "byte_size" => file.byte_size, "content_type" => file.content_type, "sha256" => sha256 }
    end
  end
end
