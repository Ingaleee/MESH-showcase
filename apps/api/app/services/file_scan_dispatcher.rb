class FileScanDispatcher
  LEASE = 60.seconds

  def self.call
    [
      [ Engagements::WorkFile, ScanWorkFileJob ],
      [ Talent::PortfolioItem, ScanPortfolioJob ],
      [ Marketplace::ProposalExample, ScanProposalExampleJob ]
    ].each do |model, job|
      due(model).order(created_at: :asc).limit(10).each do |item|
        token = claim(item)
        next unless token

        raise "file scan enqueue was rejected" unless job.perform_later(item.id, token)
      rescue StandardError => error
        model.where(id: item.id, state: "quarantined", scan_token: token).update_all(
          scan_token: nil, scan_lease_until: nil, scan_retry_at: 5.seconds.from_now, scan_error: error.class.name, updated_at: Time.current
        ) if token
        Rails.logger.warn(JSON.generate(event: "file_scan.enqueue_failed", file_id: item.id, error: error.class.name))
      end
    end
  end

  def self.due(model)
    model.where(state: "quarantined")
      .where("scan_retry_at IS NULL OR scan_retry_at <= ?", Time.current)
      .where("scan_lease_until IS NULL OR scan_lease_until <= ?", Time.current)
  end

  def self.claim(item)
    token = nil
    item.with_lock do
      now = Time.current
      next unless item.state == "quarantined"
      next if item.scan_retry_at && item.scan_retry_at > now
      next if item.scan_lease_until && item.scan_lease_until > now

      token = SecureRandom.uuid
      item.update!(scan_token: token, scan_lease_until: now + LEASE)
    end
    token
  rescue ActiveRecord::RecordNotFound
    nil
  end
end
