require "digest"

module Marketplace
  class SearchProjects
    def self.call(actor:, query: nil, category: nil, cursor: nil, limit: 12)
      query = query.to_s.strip.first(100)
      category = category.to_s.strip.first(40)
      limit = limit.to_i.clamp(1, 40)
      scope = ProjectPolicy::Scope.new(actor, Project).resolve
      if query.present?
        pattern = "%#{Project.sanitize_sql_like(query)}%"
        scope = scope.where("title ILIKE :query OR description ILIKE :query", query: pattern)
      end
      scope = scope.where(category: category) if category.present?
      digest = Digest::SHA256.hexdigest(JSON.generate([ actor&.id, query, category ]))
      verifier = Rails.application.message_verifier("project_cursor")
      if cursor.present?
        decoded = verifier.verified(cursor)
        unless decoded && decoded["query"] == digest
          raise Platform::Error.new("INVALID_CURSOR", "This cursor belongs to another query.", status: 400)
        end
        scope = scope.where(
          "(created_at, id) < (:created_at, :id)",
          created_at: Time.iso8601(decoded.fetch("created_at")), id: decoded.fetch("id")
        )
      end
      rows = scope.includes(:client).order(created_at: :desc, id: :desc).limit(limit + 1).to_a
      page = rows.first(limit)
      next_cursor = if rows.size > limit
        last = page.last
        verifier.generate({ "created_at" => last.created_at.iso8601(6), "id" => last.id, "query" => digest })
      end
      { records: page, next_cursor: next_cursor }
    end
  end
end
