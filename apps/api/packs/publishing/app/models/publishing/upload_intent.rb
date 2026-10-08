module Publishing
  class UploadIntent < Platform::Record
    self.table_name = "publishing_upload_intents"
    belongs_to :partner, class_name: "Publishing::Partner"
    belongs_to :artifact_blob, class_name: "ActiveStorage::Blob", optional: true
  end
end
