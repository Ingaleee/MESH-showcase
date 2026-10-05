class CreateMesh < ActiveRecord::Migration[8.1]
  def change
    enable_extension "pgcrypto"
    create_table :identity_accounts, id: :uuid do |t|
      t.string :email, :display_name, :password_digest, null: false
      t.string :persona, null: false, default: "client"
      t.boolean :operator, null: false, default: false
      t.integer :session_version, null: false, default: 0
      t.timestamps
    end
    add_index :identity_accounts, "lower(email)", unique: true, name: "identity_accounts_unique_email"
    add_check_constraint :identity_accounts, "email = lower(email)", name: "normalized_email"
    add_check_constraint :identity_accounts, "persona IN ('client','creator')", name: "account_persona"

    create_table :talent_profiles, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: { to_table: :identity_accounts }, index: { unique: true }
      t.string :headline, null: false
      t.text :bio, null: false, default: ""
      t.text :skills, array: true, null: false, default: []
      t.integer :rate_minor, null: false, default: 0
      t.string :currency, null: false, default: "RUB"
      t.string :accent, null: false, default: "violet"
      t.timestamps
    end
    add_check_constraint :talent_profiles, "rate_minor >= 0", name: "profile_rate_nonnegative"
    create_table :marketplace_projects, id: :uuid do |t|
      t.references :client, type: :uuid, null: false, foreign_key: { to_table: :identity_accounts }
      t.string :title, :category, null: false
      t.text :description, null: false
      t.bigint :budget_minor, null: false
      t.string :currency, null: false, default: "RUB"
      t.date :deadline, null: false
      t.string :state, null: false, default: "open"
      t.integer :brief_version, null: false, default: 1
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_check_constraint :marketplace_projects, "budget_minor > 0 AND budget_minor <= 100000000000", name: "project_budget_positive"
    add_check_constraint :marketplace_projects, "state IN ('open','awarded','closed')", name: "project_state"
    add_index :marketplace_projects, [ :state, :created_at, :id ], name: "project_feed"
    add_index :marketplace_projects, :category
    create_table :marketplace_brief_versions, id: :uuid do |t|
      t.references :project, type: :uuid, null: false, foreign_key: { to_table: :marketplace_projects }
      t.integer :version, null: false
      t.jsonb :terms, null: false
      t.timestamps
    end
    add_index :marketplace_brief_versions, [ :project_id, :version ], unique: true
    create_table :marketplace_proposals, id: :uuid do |t|
      t.references :project, type: :uuid, null: false, foreign_key: { to_table: :marketplace_projects }
      t.references :creator, type: :uuid, null: false, foreign_key: { to_table: :identity_accounts }
      t.integer :brief_version, :delivery_days, null: false
      t.bigint :price_minor, null: false
      t.text :message, null: false
      t.timestamps
    end
    add_index :marketplace_proposals, [ :project_id, :creator_id ], unique: true
    add_index :marketplace_proposals, [ :id, :project_id ], unique: true
    add_check_constraint :marketplace_proposals, "price_minor > 0 AND price_minor <= 100000000000 AND delivery_days BETWEEN 1 AND 365", name: "proposal_terms_valid"
    create_table :marketplace_awards, id: :uuid do |t|
      t.references :project, type: :uuid, null: false, foreign_key: { to_table: :marketplace_projects }, index: { unique: true }
      t.references :proposal, type: :uuid, null: false, foreign_key: { to_table: :marketplace_proposals }, index: { unique: true }
      t.timestamps
    end
    execute <<~SQL
      ALTER TABLE marketplace_awards ADD CONSTRAINT award_proposal_matches_project
      FOREIGN KEY (proposal_id, project_id) REFERENCES marketplace_proposals(id, project_id)
    SQL
    create_table :engagements_engagements, id: :uuid do |t|
      t.references :source_award, type: :uuid, null: false, foreign_key: { to_table: :marketplace_awards }, index: { unique: true }
      t.references :client, type: :uuid, null: false, foreign_key: { to_table: :identity_accounts }
      t.references :creator, type: :uuid, null: false, foreign_key: { to_table: :identity_accounts }
      t.jsonb :terms, null: false
      t.string :state, null: false, default: "agreed"
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_check_constraint :engagements_engagements, "client_id <> creator_id", name: "engagement_distinct_parties"
    add_check_constraint :engagements_engagements, "state IN ('agreed','in_progress','submitted','accepted','cancelled')", name: "engagement_state"
    create_table :engagements_submissions, id: :uuid do |t|
      t.references :engagement, type: :uuid, null: false, foreign_key: { to_table: :engagements_engagements }
      t.integer :version, null: false
      t.text :content, null: false
      t.string :sha256, null: false
      t.timestamps
    end
    add_index :engagements_submissions, [ :engagement_id, :version ], unique: true
    create_table :engagements_acceptances, id: :uuid do |t|
      t.references :engagement, type: :uuid, null: false, foreign_key: { to_table: :engagements_engagements }, index: { unique: true }
      t.references :submission, type: :uuid, null: false, foreign_key: { to_table: :engagements_submissions }, index: { unique: true }
      t.timestamps
    end
    create_table :finance_settlements, id: :uuid do |t|
      t.references :engagement, type: :uuid, null: false, foreign_key: { to_table: :engagements_engagements }, index: { unique: true }
      t.bigint :amount_minor, null: false
      t.string :currency, null: false
      t.boolean :funded, :hold, null: false, default: false
      t.text :hold_reason
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_check_constraint :finance_settlements, "amount_minor > 0", name: "settlement_amount_positive"
    create_table :finance_payment_operations, id: :uuid do |t|
      t.references :settlement, type: :uuid, null: false, foreign_key: { to_table: :finance_settlements }
      t.string :kind, null: false
      t.string :state, null: false, default: "requested"
      t.bigint :amount_minor, null: false
      t.string :currency, null: false
      t.string :scenario, null: false, default: "normal"
      t.string :external_id
      t.text :last_error
      t.integer :attempts, null: false, default: 0
      t.datetime :next_retry_at, :lease_until
      t.timestamps
    end
    add_index :finance_payment_operations, [ :settlement_id, :kind ], unique: true
    add_index :finance_payment_operations, [ :state, :next_retry_at ]
    add_check_constraint :finance_payment_operations, "kind IN ('fund','payout') AND state IN ('requested','dispatching','unknown','confirmed','failed')", name: "payment_operation_state"
    add_check_constraint :finance_payment_operations, "scenario IN ('normal','timeout_after_success','decline')", name: "payment_sandbox_scenario"
    create_table :finance_ledger_transactions, id: :uuid do |t|
      t.string :operation_key, null: false
      t.string :status, null: false, default: "draft"
      t.text :description, null: false
      t.timestamps
    end
    add_index :finance_ledger_transactions, :operation_key, unique: true
    add_check_constraint :finance_ledger_transactions, "status IN ('draft','posted')", name: "ledger_transaction_status"
    create_table :finance_ledger_entries, id: :uuid do |t|
      t.references :ledger_transaction, type: :uuid, null: false, foreign_key: { to_table: :finance_ledger_transactions }
      t.string :account_key, :currency, :direction, null: false
      t.bigint :amount_minor, null: false
      t.timestamps
    end
    add_check_constraint :finance_ledger_entries, "amount_minor > 0 AND direction IN ('debit','credit')", name: "ledger_entry_valid"
    add_index :finance_ledger_entries, [ :account_key, :currency ]
    create_table :finance_webhook_receipts, id: :uuid do |t|
      t.string :provider_event_id, null: false
      t.jsonb :payload, null: false
      t.datetime :processed_at
      t.timestamps
    end
    add_index :finance_webhook_receipts, :provider_event_id, unique: true
    create_table :finance_reconciliation_exceptions, id: :uuid do |t|
      t.references :payment_operation, type: :uuid, null: false, foreign_key: { to_table: :finance_payment_operations }
      t.string :code, null: false
      t.jsonb :details, null: false, default: {}
      t.datetime :resolved_at
      t.timestamps
    end
    add_index :finance_reconciliation_exceptions, [ :payment_operation_id, :code ], unique: true, name: "unique_reconciliation_exception"
    create_table :platform_idempotency_records, id: :uuid do |t|
      t.references :actor, type: :uuid, null: false, foreign_key: { to_table: :identity_accounts }
      t.string :operation, :key, :fingerprint, null: false
      t.jsonb :response
      t.timestamps
    end
    add_index :platform_idempotency_records, [ :actor_id, :operation, :key ], unique: true, name: "idempotency_scope"
    create_table :platform_outbox_events, id: :uuid do |t|
      t.string :event_type, :aggregate_type, :correlation_id, null: false
      t.integer :schema_version, null: false, default: 1
      t.uuid :aggregate_id, null: false
      t.integer :aggregate_version, null: false
      t.jsonb :payload, null: false
      t.jsonb :trace_context, null: false, default: {}
      t.timestamps
    end
    create_table :platform_deliveries, id: :uuid do |t|
      t.references :outbox_event, type: :uuid, null: false, foreign_key: { to_table: :platform_outbox_events }
      t.string :consumer, null: false
      t.string :state, null: false, default: "pending"
      t.integer :attempts, null: false, default: 0
      t.datetime :enqueued_at, :processed_at
      t.text :last_error
      t.timestamps
    end
    add_index :platform_deliveries, [ :outbox_event_id, :consumer ], unique: true
    add_index :platform_deliveries, [ :state, :enqueued_at ]
    create_table :platform_audit_entries, id: :uuid do |t|
      t.uuid :actor_id
      t.string :action, :resource_type, :correlation_id, null: false
      t.uuid :resource_id, null: false
      t.jsonb :details, null: false, default: {}
      t.timestamps
    end
    create_table :notifications_notifications, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: { to_table: :identity_accounts }
      t.references :outbox_event, type: :uuid, null: false, foreign_key: { to_table: :platform_outbox_events }
      t.string :title, :body, :resource_path, null: false
      t.datetime :read_at
      t.timestamps
    end
    add_index :notifications_notifications, [ :account_id, :outbox_event_id ], unique: true, name: "notification_effect_unique"
    create_table :talent_portfolio_items, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: { to_table: :identity_accounts }
      t.string :title, null: false
      t.string :state, null: false, default: "quarantined"
      t.string :sha256, :scan_error
      t.timestamps
    end
  end
end
