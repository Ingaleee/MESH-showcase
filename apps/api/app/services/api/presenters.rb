module Api
  module Presenters
    def self.account(account, private_fields: false)
      return nil unless account

      result = account.attributes.slice("id", "display_name", "persona")
      result.merge!("email" => account.email, "operator" => account.operator?) if private_fields
      result
    end

    def self.profile(profile)
      profile.attributes.slice("id", "account_id", "headline", "bio", "skills", "rate_minor", "currency", "accent")
        .merge("account" => account(profile.account))
    end

    def self.project(project)
      project.attributes.slice("id", "title", "description", "category", "budget_minor", "currency", "state", "accepting_proposals", "brief_version", "lock_version", "expected_result", "deliverables", "requirements", "skills", "reference_urls")
        .merge("deadline" => project.deadline.iso8601, "created_at" => project.created_at.iso8601, "client" => account(project.client))
    end

    def self.proposal(proposal, profile: nil)
      proposal.attributes.slice("id", "price_minor", "delivery_days", "message", "brief_version")
        .merge("creator" => account(proposal.creator), "example" => proposal.example && proposal_example(proposal.example), "created_at" => proposal.created_at.iso8601, "profile" => profile && self.profile(profile))
    end

    def self.proposal_example(item)
      {
        id: item.id, state: item.state, filename: item.file.filename.to_s,
        byte_size: item.file.byte_size, content_type: item.file.content_type
      }
    end

    def self.work_file(item)
      item.manifest.merge("state" => item.state, "submission_id" => item.submission_id)
    end

    def self.engagement(engagement, project_id:, submissions: [], feedback: [], submissions_next_cursor: nil, feedback_next_cursor: nil)
      engagement.attributes.slice("id", "client_id", "creator_id", "state", "terms", "lock_version")
        .merge(
          "submissions" => submissions.sort_by(&:version).reverse.map { |row| row.attributes.slice("id", "version", "content", "sha256", "title", "ready_for_acceptance", "manifest_sha256", "manifest_format").merge("created_at" => row.created_at.iso8601, "files" => row.work_files.map { |file| work_file(file) }) },
          "feedback" => feedback.sort_by(&:created_at).map { |row| row.attributes.slice("id", "submission_id", "kind", "content").merge("created_at" => row.created_at.iso8601, "actor" => account(row.actor)) },
          "client" => account(engagement.client), "creator" => account(engagement.creator), "project_id" => project_id,
          "created_at" => engagement.created_at.iso8601, "started_at" => engagement.started_at&.iso8601,
          "accepted_at" => engagement.acceptance&.created_at&.iso8601,
          "accepted_submission_id" => engagement.acceptance&.submission_id,
          "submissions_next_cursor" => submissions_next_cursor, "feedback_next_cursor" => feedback_next_cursor
        )
    end

    def self.operation(operation)
      operation.attributes.slice("id", "kind", "state", "amount_minor", "currency", "scenario", "external_id", "attempts", "last_error")
    end
  end
end
