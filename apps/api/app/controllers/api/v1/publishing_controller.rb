module Api
  module V1
    class PublishingController < ApplicationController
      before_action :require_operator!
      before_action :require_enabled!
      after_action -> { response.headers["Cache-Control"] = "private, no-store" }

      def index
        partners = Publishing::Partner.where(owner_id: current_account.id).order(created_at: :desc).limit(20)
        candidates = Publishing::Candidate.where(partner_id: partners.map(&:id)).includes(:partner, :artifact_blob).order(created_at: :desc, id: :desc).limit(30)
        validations = Publishing::LatestValidations.call(candidate_ids: candidates.map(&:id))
        fingerprints = candidates.to_h { |row| [ row.id, Publishing::Settings.fingerprint(row) ] }
        deployments = Publishing::Deployment.where(partner_id: partners.map(&:id)).order(created_at: :desc).limit(30)
        render json: {
          partners: partners.map { |row| partner_json(row) },
          candidates: candidates.map { |row| candidate_json(row) },
          validations: validations.map { |row| validation_json(row).merge(current_inputs_match: fingerprints[row.candidate_id] == row.input_fingerprint) },
          deployments: deployments.map { |row| deployment_json(row) },
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

      def diagnose
        deployment = Publishing::Deployment.where(partner_id: owned_partners.select(:id)).includes(:partner, candidate: :artifact_blob, validation: :candidate).find(params[:deployment_id])
        render json: {
          schema_version: 1, operation_id: deployment.id, state: deployment.state, artifact_sha256: deployment.candidate.artifact_sha256,
          policy_version: deployment.validation.policy_version, input_fingerprint: deployment.validation.input_fingerprint,
          current_inputs_match: Publishing::Settings.fingerprint(deployment.candidate) == deployment.validation.input_fingerprint,
          correlation_id: deployment.correlation_id, attempts: deployment.attempts, last_error: deployment.last_error,
          local_confirmed_at: deployment.confirmed_at, remote_sequence: deployment.remote_sequence,
          next_action: deployment.state == "unknown" ? "Lookup remote state by the same operation ID; do not create another POST." : "Inspect the validation report and release history.",
          reproduce: "mesh-publish diagnose #{deployment.id}"
        }
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
