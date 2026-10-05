module Api
  module V1
    class ProjectsController < ApplicationController
      skip_before_action :require_account!, only: %i[index show]

      def index
        page = Marketplace::SearchProjects.call(
          actor: current_account, query: params[:q], category: params[:category],
          cursor: params[:cursor], limit: params.fetch(:limit, 12)
        )
        render json: { data: page[:records].map { |project| Presenters.project(project) }, next_cursor: page[:next_cursor] }
      end

      def show
        project = Marketplace::Project.find(params[:id])
        authorize project, :show?
        proposal_count = project.proposals.count
        page = Marketplace::ProposalPage.call(project: project, actor: current_account, cursor: params[:cursor], limit: params.fetch(:limit, 20), query: params[:q], sort: params.fetch(:sort, "newest"), version: params.fetch(:brief_filter, "all"), ids: params[:ids])
        proposals = page.fetch(:records)
        profiles = Talent::Directory.for_accounts(proposals.map(&:creator_id)).index_by(&:account_id)
        history = Marketplace::BriefHistory.call(project: project)
        render json: {
          project: Presenters.project(project), proposals: proposals.map { |row| Presenters.proposal(row, profile: profiles[row.creator_id]) },
          proposal_count: proposal_count, brief_history: history,
          next_proposal_cursor: page.fetch(:next_cursor), matched_proposal_count: page.fetch(:matched_count), current_proposal_count: page.fetch(:current_count),
          owner_context: current_account&.id == project.client_id ? Marketplace::OwnerOverview.call(actor: current_account, project: project, history: history) : nil
        }
      end

      def create
        result = Marketplace::CreateProject.call(actor: current_account, input: project_input, key: idempotency_key)
        render json: Presenters.project(Marketplace::Project.find(result[:id])), status: :created
      end

      def update
        project = Marketplace::Project.find(params[:id])
        authorize project, :update?
        result = Marketplace::ReviseBrief.call(
          actor: current_account, project: project, input: project_input,
          version: Platform::Input.integer(params.require(:version)), key: idempotency_key
        )
        render json: Presenters.project(Marketplace::Project.find(result[:id]))
      end

      def propose
        project = Marketplace::Project.find(params[:id])
        authorize project, :propose?
        input = params.require(:proposal).permit(:price_minor, :delivery_days, :message, :brief_version, :example_id).to_h.symbolize_keys
        %i[price_minor delivery_days brief_version].each { |key| input[key] = Platform::Input.integer(input.fetch(key)) }
        render json: Marketplace::SubmitProposal.call(actor: current_account, project: project, input: input, key: idempotency_key), status: :created
      end

      def award
        project = Marketplace::Project.find(params[:id])
        authorize project, :award?
        render json: Marketplace::AwardProposal.call(
          actor: current_account, project: project, proposal_id: params.require(:proposal_id),
          brief_version: Platform::Input.integer(params.require(:brief_version)), key: idempotency_key
        ), status: :created
      end

      def intake
        project = Marketplace::Project.find(params[:id])
        authorize project, :update?
        render json: Marketplace::ChangeIntake.call(
          actor: current_account, project: project, accepting: params.fetch(:accepting_proposals),
          version: Platform::Input.integer(params.require(:version)), key: idempotency_key
        )
      end

      private

      def project_input
        input = params.require(:project).permit(
          :title, :description, :category, :budget_minor, :currency, :deadline, :expected_result,
          deliverables: [], requirements: [], skills: [], reference_urls: []
        ).to_h.symbolize_keys
        input[:budget_minor] = Platform::Input.integer(input.fetch(:budget_minor)) if input.key?(:budget_minor)
        input
      end
    end
  end
end
