module Publishing
  class LatestValidations
    def self.call(candidate_ids:)
      return [] if candidate_ids.empty?
      raise ArgumentError, "bounded candidate list required" if candidate_ids.length > 30
      Validation.find_by_sql([ <<~SQL, { ids: candidate_ids } ])
        SELECT latest.*
        FROM publishing_candidates AS candidate
        JOIN LATERAL (
          SELECT validation.* FROM publishing_validations AS validation
          WHERE validation.candidate_id = candidate.id
          ORDER BY validation.created_at DESC, validation.id DESC
          LIMIT 1
        ) AS latest ON TRUE
        WHERE candidate.id IN (:ids)
        ORDER BY latest.created_at DESC, latest.id DESC
      SQL
    end
  end
end
