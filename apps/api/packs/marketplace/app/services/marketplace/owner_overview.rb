module Marketplace
  class OwnerOverview
    def self.call(actor:, project:, history:)
      raise Platform::Error.new("FORBIDDEN", "Owner access required.", status: 403) unless actor&.id == project.client_id

      award = Award.find_by(project_id: project.id)
      agreement = award && Engagements::ReadModel.for_award(award.id, actor_id: actor.id)
      events = history.map do |row|
        { id: "brief-#{row[:version]}", kind: row[:version] == 1 ? "published" : "brief_revised", created_at: row[:created_at], brief_version: row[:version], actor_name: nil }
      end
      project.proposals.includes(:creator).order(created_at: :desc, id: :desc).limit(50).each do |proposal|
        events << { id: proposal.id, kind: "proposal_received", created_at: proposal.created_at.iso8601, brief_version: proposal.brief_version, actor_name: proposal.creator.display_name }
      end
      Platform::AuditEntry.where(resource_type: "Marketplace::Project", resource_id: project.id, action: %w[project.intake_paused project.intake_resumed proposal.awarded]).order(created_at: :desc).limit(50).each do |entry|
        events << { id: entry.id, kind: entry.action.split(".").last, created_at: entry.created_at.iso8601, brief_version: nil, actor_name: nil }
      end
      {
        award: award && { proposal_id: award.proposal_id, engagement_id: agreement.fetch(:id), engagement_state: agreement.fetch(:state), creator_name: agreement.fetch(:creator_name), created_at: award.created_at.iso8601 },
        events: events.sort_by { |event| [ event[:created_at], event[:id] ] }.reverse.first(50)
      }
    end
  end
end
