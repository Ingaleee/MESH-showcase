module Api
  module V1
    class EngagementsController < ApplicationController
      def index
        scope = policy_scope(Engagements::Engagement).includes(:client, :creator, :acceptance).order(created_at: :desc).limit(40)
        projects = Marketplace::Award.where(id: scope.map(&:source_award_id)).pluck(:id, :project_id).to_h
        render json: { data: scope.map { |engagement| Presenters.engagement(engagement, project_id: projects[engagement.source_award_id]) } }
      end

      def show
        engagement = authorized_engagement
        page = Engagements::HistoryPage.call(engagement: engagement, actor: current_account, versions_cursor: params[:versions_cursor], feedback_cursor: params[:feedback_cursor], limit: params.fetch(:limit, 20))
        render json: Presenters.engagement(engagement, project_id: Marketplace::Award.find(engagement.source_award_id).project_id, **page)
      end

      def submit
        engagement = authorized_engagement
        authorize engagement, :submit?
        render json: Engagements::SubmitWork.call(actor: current_account, engagement: engagement, content: params.require(:content), title: params.fetch(:title, ""), ready_for_acceptance: params.fetch(:ready_for_acceptance, true), file_ids: params.fetch(:file_ids, []), key: idempotency_key), status: :created
      end

      def start
        engagement = authorized_engagement
        render json: Engagements::StartWork.call(actor: current_account, engagement: engagement, key: idempotency_key)
      end

      def feedback
        engagement = authorized_engagement
        render json: Engagements::RecordFeedback.call(actor: current_account, engagement: engagement, content: params.require(:content), submission_id: params[:submission_id], kind: params.fetch(:kind, "comment"), key: idempotency_key), status: :created
      end

      def archive
        engagement = authorized_engagement
        bytes = Engagements::BuildArchive.call(actor: current_account, engagement: engagement, submission_id: params.require(:submission_id))
        response.headers["Cache-Control"] = "private, no-store"
        response.headers["X-Content-Type-Options"] = "nosniff"
        send_data bytes, type: "application/zip", disposition: "attachment", filename: "mesh-version-#{params[:submission_id]}.zip"
      end

      def accept
        engagement = authorized_engagement
        authorize engagement, :accept?
        render json: Engagements::AcceptSubmission.call(actor: current_account, engagement: engagement, submission_id: params.require(:submission_id), key: idempotency_key)
      end

      private

      def authorized_engagement
        engagement = Engagements::Engagement.includes(:client, :creator, :acceptance).find(params[:id])
        authorize engagement, :show?
        engagement
      end
    end
  end
end
