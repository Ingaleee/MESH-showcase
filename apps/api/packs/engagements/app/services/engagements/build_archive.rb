require "zip"

module Engagements
  class BuildArchive
    def self.call(actor:, engagement:, submission_id:)
      unless [ engagement.client_id, engagement.creator_id ].include?(actor.id)
        raise Platform::Error.new("FORBIDDEN", "Participant access required.", status: 403)
      end
      submission = engagement.submissions.find(submission_id)
      files = submission.work_files.includes(file_attachment: :blob).to_a
      raise Platform::Error.new("NO_FILES", "This version has no files.", status: 404) if files.empty?
      raise Platform::Error.new("FILE_QUARANTINED", "Wait for all files to pass verification.", status: 409) unless files.all? { |file| file.state == "available" }
      raise Platform::Error.new("ZIP_LIMIT", "Download files separately above 50 MB.", status: 422) if files.sum { |file| file.file.byte_size } > 50.megabytes
      Zip::OutputStream.write_buffer do |zip|
        files.sort_by(&:id).each_with_index do |file, index|
          name = File.basename(file.file.filename.to_s.tr("\\", "/")).gsub(/[\x00-\x1f]/, "_")
          zip.put_next_entry("#{index + 1}-#{name}")
          file.file.download { |chunk| zip.write(chunk) }
        end
      end.string
    end
  end
end
