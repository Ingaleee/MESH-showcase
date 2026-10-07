module Talent
  class Directory
    def self.for_accounts(account_ids)
      Profile.includes(:account).where(account_id: account_ids)
    end

    # Keep matching IDs in SQL so proposal search is not capped by the public directory page.
    def self.matching_account_ids(query:)
      pattern = "%#{Profile.sanitize_sql_like(query)}%"
      Profile.where("headline ILIKE :q OR bio ILIKE :q OR array_to_string(skills, ' ') ILIKE :q", q: pattern).select(:account_id)
    end

    def self.eligible?(account_id)
      Profile.exists?(account_id: account_id)
    end

    def self.search(query: nil)
      scope = Profile.includes(:account).order(created_at: :asc, id: :asc)
      if query.present?
        pattern = "%#{Profile.sanitize_sql_like(query.to_s.first(100))}%"
        text_matches = scope.where("headline ILIKE :q OR bio ILIKE :q OR array_to_string(skills, ' ') ILIKE :q", q: pattern)
        named_accounts = Identity::Account.where("display_name ILIKE ?", pattern).select(:id)
        scope = text_matches.or(scope.where(account_id: named_accounts))
      end
      scope.limit(40)
    end
  end
end
