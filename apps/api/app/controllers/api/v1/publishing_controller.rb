module Api
  module V1
    class PublishingController < ApplicationController
      before_action :require_operator!
      before_action :require_enabled!
      after_action -> { response.headers["Cache-Control"] = "private, no-store" }

      def index
        pages = {
          partners: Publishing::HistoryPage.call(scope: owned_partners, actor: current_account, kind: "partners", cursor: params[:partners_cursor], limit: params.fetch(:limit, 20)),
          candidates: Publishing::HistoryPage.call(scope: Publishing::Candidate.where(partner_id: owned_partners.select(:id)).includes(:partner, :artifact_blob), actor: current_account, kind: "candidates", cursor: params[:candidates_cursor], limit: params.fetch(:limit, 30)),
          deployments: Publishing::HistoryPage.call(scope: Publishing::Deployment.where(partner_id: owned_partners.select(:id)), actor: current_account, kind: "deployments", cursor: params[:deployments_cursor], limit: params.fetch(:limit, 30))
        }
        partners = pages.fetch(:partners).fetch(:records)
        candidates = pages.fetch(:candidates).fetch(:records)
        validations = Publishing::LatestValidations.call(candidate_ids: candidates.map(&:id))
        fingerprints = candidates.to_h { |row| [ row.id, Publishing::Settings.fingerprint_status(row) ] }
        deployments = pages.fetch(:deployments).fetch(:records)
        active = Publishing::Deployment.where(id: partners.filter_map(&:active_deployment_id), partner_id: owned_partners.select(:id)).order(:id)
        render json: {
          partners: partners.map { |row| partner_json(row) },
          candidates: candidates.map { |row| candidate_json(row) },
          validations: validations.map { |row|
            inputs = fingerprints.fetch(row.candidate_id)
            validation_json(row).merge(current_inputs_match: inputs.fetch(:fingerprint) && inputs.fetch(:fingerprint) == row.input_fingerprint,
              configuration_error: inputs.fetch(:error))
          },
          deployments: deployments.map { |row| deployment_json(row) },
          active_deployments: active.map { |row| deployment_json(row) },
          next_cursors: pages.transform_values { |page| page.fetch(:next_cursor) },
          policy_version: Publishing::Settings.policy_version
        }
      end

      def register
        render json: Publishing::RegisterPartner.call(actor: current_account, input: params.require(:partner).permit(:name, :origin, :credential_ref).to_h, key: idempotency_key), status: :created
      end

      def submit
        partner = owned_partners.find(params[:partner_id])
        upload = params.require(:artifact)
        raise Platform::Error.new("PACKAGE_LIMIT", "Use a small ZIP upload.") unless upload.respond_to?(:read) && upload.size <= Publishing::Settings::ARTIFACT_LIMIT
        bytes = upload.read(Publishing::Settings::ARTIFACT_LIMIT + 1)
        manifest = JSON.parse(params.require(:manifest), max_nesting: 10)
        render json: Publishing::SubmitCandidate.call(actor: current_account, partner: partner, manifest: manifest, bytes: bytes, key: idempotency_key), status: :created
      rescue JSON::ParserError
        raise Platform::Error.new("MANIFEST_INVALID", "Supply a JSON manifest.")
      end

      def validate
        render json: Publishing::RequestValidation.call(actor: current_account, candidate: owned_candidate, key: idempotency_key), status: :accepted
      end

      def publish
        render json: Publishing::RequestDeployment.call(
          actor: current_account, candidate: owned_candidate, validation_id: params.require(:validation_id),
          key: idempotency_key, scenario: params.fetch(:scenario, "normal"), rollback_of_id: params[:rollback_of_id]
        ), status: :accepted
      end

      def artifact
        candidate = owned_candidate
        bytes = Publishing::ValidateCandidate.read_bytes(candidate)
        unless Digest::SHA256.hexdigest(bytes) == candidate.artifact_sha256
          raise Platform::Error.new("ARTIFACT_DIGEST_CHANGED", "Stored artifact integrity check failed.", status: 409)
        end
        response.headers["X-Content-Type-Options"] = "nosniff"
        send_data bytes, type: "application/zip", disposition: "attachment", filename: "#{candidate.artifact_sha256}.zip"
      end

      def diagnose
        deployment = Publishing::Deployment.where(partner_id: owned_partners.select(:id)).includes(:partner, candidate: :artifact_blob, validation: :candidate).find(params[:deployment_id])
        render json: Publishing::DeploymentDiagnostic.call(deployment: deployment)
      end

      def reconcile
        deployment = Publishing::Deployment.where(partner_id: owned_partners.select(:id)).find(params[:deployment_id])
        deployment.with_lock do
          if deployment.state == "unknown"
            deployment.update!(consecutive_failures: 0, next_enqueue_at: Time.current)
            Platform::Events.audit(action: "publishing.lookup.requested", resource: deployment)
          end
        end
        render json: { id: deployment.id, state: deployment.state }, status: :accepted
      end

      private

      def require_enabled!
        raise Platform::Error.new("PUBLISHING_DISABLED", "Publishing laboratory is disabled.", status: 503) unless ENV.fetch("MESH_PUBLISHING_ENABLED", "false") == "true"
      end

      def owned_partners
        Publishing::Partner.where(owner_id: current_account.id)
      end

      def owned_candidate
        Publishing::Candidate.where(partner_id: owned_partners.select(:id)).find(params[:candidate_id])
      end

      def partner_json(row)
        row.as_json(only: %i[id name contract_version active_deployment_id active_sequence])
      end

      def candidate_json(row)
        row.as_json(only: %i[id partner_id manifest artifact_sha256 manifest_sha256 created_at correlation_id])
      end

      def validation_json(row)
        row.as_json(only: %i[id candidate_id state policy_version input_fingerprint report last_error attempts completed_at created_at])
      end

      def deployment_json(row)
        row.as_json(only: %i[id partner_id candidate_id validation_id kind state last_error attempts remote_sequence confirmed_at created_at correlation_id rollback_of_id])
      end
    end
  end
end
