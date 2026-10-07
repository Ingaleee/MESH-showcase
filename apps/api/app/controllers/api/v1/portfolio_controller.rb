require "digest"

module Api
  module V1
    class PortfolioController < ApplicationController
      MAX_BYTES = 10.megabytes
      TYPES = %w[image/png image/jpeg application/pdf text/plain].freeze

      def index
        rows = Talent::PortfolioItem.where(account_id: current_account.id).order(created_at: :desc).limit(200)
        render json: { data: rows.map { |row| row.attributes.slice("id", "title", "state", "sha256", "scan_error") } }
      end

      def create
        upload = params.require(:file)
        unless upload.is_a?(ActionDispatch::Http::UploadedFile) && upload.size.positive? && upload.size <= MAX_BYTES
          raise Platform::Error.new("INVALID_FILE", "Upload a file smaller than 10 MB.")
        end
        content_type = Marcel::MimeType.for(upload.tempfile)
        raise Platform::Error.new("INVALID_FILE_TYPE", "File type is not allowed.") unless TYPES.include?(content_type)

        item = Talent::PortfolioItem.transaction do
          row = Talent::PortfolioItem.create!(account_id: current_account.id, title: params.require(:title), sha256: Digest::SHA256.file(upload.tempfile.path).hexdigest)
          filename = File.basename(upload.original_filename.tr("\\", "/")).first(160)
          row.file.attach(io: upload.tempfile, filename: filename, content_type: content_type)
          row
        end
        render json: { id: item.id, state: item.state }, status: :created
      end

      def download
        item = Talent::PortfolioItem.where(account_id: current_account.id).find(params[:id])
        raise Platform::Error.new("FILE_QUARANTINED", "File is not available yet.", status: 409) unless item.state == "available"

        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Cache-Control"] = "private, no-store"
        send_data item.file.download, type: item.file.content_type, disposition: "attachment", filename: item.file.filename.to_s
      end
    end
  end
end
