require "digest"

module Api
  module V1
    class WorkFilesController < ApplicationController
      TYPES = %w[image/png image/jpeg application/pdf application/zip application/x-zip-compressed].freeze

      def index
        engagement = authorized_engagement
        files = Engagements::WorkFile.where(engagement: engagement).includes(file_attachment: :blob)
        files = files.where.not(submission_id: nil) unless current_account.id == engagement.creator_id
        render json: { data: files.order(created_at: :desc).limit(200).map { |item| Presenters.work_file(item) } }
      end

      def create
        engagement = authorized_engagement
        authorize engagement, :submit?
        upload = params.require(:file)
        unless upload.is_a?(ActionDispatch::Http::UploadedFile) && upload.size.positive? && upload.size <= 20.megabytes
          raise Platform::Error.new("INVALID_FILE", "Choose a file up to 20 MB.")
        end
        type = Marcel::MimeType.for(upload.tempfile)
        raise Platform::Error.new("INVALID_FILE_TYPE", "Choose PDF, PNG, JPG or ZIP.") unless TYPES.include?(type)
        filename = File.basename(upload.original_filename.tr("\\", "/")).first(160)
        sha256 = Digest::SHA256.file(upload.tempfile.path).hexdigest
        result = Platform::Idempotency.call(actor_id: current_account.id, operation: "work-file:#{engagement.id}", key: idempotency_key, input: { sha256: sha256, filename: filename, type: type }) do
          engagement.lock!
          unless %w[agreed in_progress submitted].include?(engagement.state)
            raise Platform::Error.new("WORK_CLOSED", "The agreement is closed.", status: 409)
          end
          if Engagements::WorkFile.where(engagement: engagement, submission_id: nil).count >= 20
            raise Platform::Error.new("FILE_LIMIT", "Remove unused files first.", status: 409)
          end
          item = Engagements::WorkFile.create!(engagement: engagement, creator: current_account, sha256: sha256)
          item.file.attach(io: upload.tempfile, filename: filename, content_type: type)
          { id: item.id }
        end
        render json: Presenters.work_file(Engagements::WorkFile.find(result.fetch(:id))), status: :created
      end

      def destroy
        engagement = authorized_engagement
        item = Engagements::WorkFile.where(engagement: engagement, creator_id: current_account.id).find(params[:id])
        item.with_lock do
          raise Platform::Error.new("FILE_SUBMITTED", "A version's file cannot be removed.", status: 409) if item.submission_id.present?
          item.destroy!
        end
        head :no_content
      end

      def show
        render json: Presenters.work_file(visible_file)
      end

      def download
        item = visible_file
        raise Platform::Error.new("FILE_QUARANTINED", "The file is not available.", status: 409) unless item.state == "available"
        response.headers["Cache-Control"] = "private, no-store"
        response.headers["X-Content-Type-Options"] = "nosniff"
        send_data item.file.download, type: item.file.content_type, disposition: "attachment", filename: item.file.filename.to_s
      end

      private

      def authorized_engagement
        engagement = Engagements::Engagement.find(params[:engagement_id])
        authorize engagement, :show?
        engagement
      end

      def visible_file
        item = Engagements::WorkFile.where(engagement: authorized_engagement).find(params[:id])
        raise ActiveRecord::RecordNotFound unless item.visible_to?(current_account)
        item
      end
    end
  end
end
