class HardenBackgroundClaimsAndLoginLimits < ActiveRecord::Migration[8.1]
  def change
    add_column :platform_deliveries, :claim_token, :uuid
    add_check_constraint :platform_deliveries, "state IN ('pending', 'enqueued', 'processed', 'failed')", name: "delivery_state_valid"

    %i[talent_portfolio_items marketplace_proposal_examples engagements_work_files].each do |table|
      add_column table, :scan_token, :uuid
      add_column table, :scan_lease_until, :datetime
      add_column table, :scan_retry_at, :datetime
      add_column table, :scan_attempts, :integer, null: false, default: 0
      add_index table, [ :scan_retry_at, :scan_lease_until ], where: "state = 'quarantined'", name: "#{table}_scan_due"
    end

    create_table :platform_rate_limit_buckets, id: false do |t|
      t.string :key_digest, primary_key: true
      t.integer :attempts, null: false, default: 0
      t.datetime :expires_at, null: false
    end
    add_index :platform_rate_limit_buckets, :expires_at
    add_check_constraint :platform_rate_limit_buckets, "attempts >= 0", name: "rate_limit_attempts_valid"
  end
end
