module Marketplace
  class BriefHistory
    def self.call(project:)
      records = BriefVersion.where(project_id: project.id).order(version: :desc).limit(51).to_a.reverse
      previous = records.size > 50 ? records.shift : nil
      records.map do |record|
        changed = previous ? Project::BRIEF_FIELDS.select { |field| normalized(record.terms, field) != normalized(previous.terms, field) } : []
        previous = record
        { version: record.version, created_at: record.created_at.iso8601, changed_fields: changed }
      end
    end

    def self.normalized(terms, field)
      terms.fetch(field) { %w[deliverables requirements skills reference_urls].include?(field) ? [] : field == "expected_result" ? "" : nil }
    end
    private_class_method :normalized
  end
end
