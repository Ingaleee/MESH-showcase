module Marketplace
  class ProposalPage
    SORTS = %w[newest price days].freeze
    VERSIONS = %w[all current old].freeze

    def self.call(project:, actor:, cursor: nil, limit: 20, query: nil, sort: "newest", version: "all", ids: nil)
      limit = Integer(limit.to_s, 10).clamp(1, 40)
      query = query.to_s.strip.first(100)
      raise Platform::Error.new("INVALID_FILTER", "Unknown proposal sort or version.", status: 400) unless SORTS.include?(sort) && VERSIONS.include?(version)
      selected = ids.nil? ? nil : ids.to_s.split(",").uniq.sort
      if selected && (selected.size > 100 || selected.any? { |id| !id.match?(/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/i) })
        raise Platform::Error.new("INVALID_FILTER", "At most 100 proposal IDs are allowed.", status: 400)
      end
      scope = project.proposals
      scope = scope.where(creator_id: actor&.id) unless project.client_id == actor&.id
      current_count = scope.where(brief_version: project.brief_version).count
      scope = scope.where(id: selected) unless selected.nil?
      scope = scope.where(brief_version: project.brief_version) if version == "current"
      scope = scope.where.not(brief_version: project.brief_version) if version == "old"
      if query.present?
        pattern = "%#{Proposal.sanitize_sql_like(query)}%"
        scope = scope.joins(:creator)
        text_matches = scope.where("identity_accounts.display_name ILIKE :query OR marketplace_proposals.message ILIKE :query", query: pattern)
        scope = text_matches.or(scope.where(creator_id: Talent::Directory.matching_account_ids(query: query)))
      end
      matched_count = scope.count
      context = [ "proposals", project.id, actor&.id, query, sort, version, project.brief_version, selected ]
      position = Platform::ReadCursor.decode(cursor, context: context)
      column = { "price" => "price_minor", "days" => "delivery_days" }[sort]
      if position
        boundary = "(marketplace_proposals.created_at, marketplace_proposals.id) < (:time, :id)"
        boundary = "marketplace_proposals.#{column} > :value OR (marketplace_proposals.#{column} = :value AND #{boundary})" if column
        scope = scope.where(boundary, time: position.fetch("time"), id: position.fetch("id"), value: position["value"])
      end
      ordering = column ? { column => :asc, created_at: :desc, id: :desc } : { created_at: :desc, id: :desc }
      rows = scope.order(ordering).limit(limit + 1).includes(:creator, example: { file_attachment: :blob }).to_a
      records = rows.first(limit)
      next_cursor = if rows.size > limit
        last = records.last
        Platform::ReadCursor.encode({ "time" => last.created_at.iso8601(6), "id" => last.id, "value" => column && last.public_send(column) }, context: context)
      end
      { records: records, next_cursor: next_cursor, matched_count: matched_count, current_count: current_count }
    rescue ArgumentError, TypeError
      raise Platform::Error.new("INVALID_FILTER", "The page limit must be an integer.", status: 400)
    end
  end
end
