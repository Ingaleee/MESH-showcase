module Publishing
  class HistoryPage
    def self.call(scope:, actor:, kind:, cursor: nil, limit: 30)
      size = Platform::Input.integer(limit).clamp(1, 30)
      context = [ "publishing_history_v1", actor.id, kind ]
      position = Platform::ReadCursor.decode(cursor, context: context)
      if position
        unless position["id"].to_s.match?(/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/)
          raise Platform::Error.new("INVALID_CURSOR", "Invalid history position.", status: 400)
        end
        moment = Time.iso8601(position.fetch("created_at"))
        scope = scope.where("(created_at, id) < (?, ?)", moment, position.fetch("id"))
      end
      rows = scope.order(created_at: :desc, id: :desc).limit(size + 1).to_a
      records = rows.first(size)
      last = records.last
      next_cursor = if rows.length > size
        Platform::ReadCursor.encode({ "created_at" => last.created_at.iso8601(6), "id" => last.id }, context: context)
      end
      { records: records, next_cursor: next_cursor }
    rescue ArgumentError, KeyError
      raise Platform::Error.new("INVALID_CURSOR", "Invalid history position or page size.", status: 400)
    end
  end
end
