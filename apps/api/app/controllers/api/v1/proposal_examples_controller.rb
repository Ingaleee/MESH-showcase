require "digest"

module Api
  module V1
    class ProposalExamplesController < ApplicationController
      MAX_BYTES = 10.megabytes
      TYPES = %w[image/png image/jpeg application/pdf].freeze

      def create
        project = Marketplace::Project.find(params[:project_id])
        authorize project, :propose?
        raise Platform::Error.new("PROFILE_REQUIRED", "Create a creator profile first.") unless Talent::Directory.eligible?(current_account.id)

        upload = params.require(:file)
        unless upload.is_a?(ActionDispatch::Http::UploadedFile) && upload.size.positive? && upload.size <= MAX_BYTES
          raise Platform::Error.new("INVALID_FILE", "Upload a non-empty file up to 10 MB.")
        end
        content_type = Marcel::MimeType.for(upload.tempfile)
        raise Platform::Error.new("INVALID_FILE_TYPE", "Choose a PDF, PNG or JPEG file.") unless TYPES.include?(content_type)

        filename = File.basename(upload.original_filename.tr("\\", "/")).first(160)
        sha256 = Digest::SHA256.file(upload.tempfile.path).hexdigest
        result = Platform::Idempotency.call(
          actor_id: current_account.id, operation: "proposal-example:#{project.id}", key: idempotency_key,
          input: { sha256: sha256, filename: filename, content_type: content_type }
        ) do
          project.lock!
          raise Platform::Error.new("PROJECT_CLOSED", "This project is no longer open.", status: 409) unless project.state == "open"
          raise Platform::Error.new("PROPOSALS_PAUSED", "The client has paused proposals.", status: 409) unless project.accepting_proposals
          if Marketplace::ProposalExample.where(project_id: project.id, creator_id: current_account.id, proposal_id: nil).count >= 10
            raise Platform::Error.new("FILE_LIMIT", "Remove unused examples before uploading another file.", status: 409)
          end
          item = Marketplace::ProposalExample.create!(project: project, creator: current_account, sha256: sha256)
          item.file.attach(io: upload.tempfile, filename: filename, content_type: content_type)
          { id: item.id }
        end
        render json: Presenters.proposal_example(Marketplace::ProposalExample.find(result.fetch(:id))), status: :created
      end

      def show
        render json: Presenters.proposal_example(visible_example)
      end

      def destroy
        item = Marketplace::ProposalExample.where(project_id: params[:project_id], creator_id: current_account.id).find(params[:id])
        item.with_lock do
          raise Platform::Error.new("EXAMPLE_SUBMITTED", "A submitted example cannot be removed.", status: 409) if item.proposal_id.present?

          item.destroy!
        end
        head :no_content
      end

      def download
        item = visible_example
        raise Platform::Error.new("FILE_QUARANTINED", "The file has not passed verification.", status: 409) unless item.state == "available"

        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Cache-Control"] = "private, no-store"
        send_data item.file.download, type: item.file.content_type, disposition: "attachment", filename: item.file.filename.to_s
      end

      private

      def visible_example
        item = Marketplace::ProposalExample.where(project_id: params[:project_id]).find(params[:id])
        raise ActiveRecord::RecordNotFound unless item.visible_to?(current_account)

        item
      end
    end
  end
end
