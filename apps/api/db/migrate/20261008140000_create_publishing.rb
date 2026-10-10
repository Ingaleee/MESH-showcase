class CreatePublishing < ActiveRecord::Migration[8.1]
  def change
    create_table :publishing_partners, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :owner_id, null: false
      t.string :name, null: false
      t.string :origin, null: false
      t.string :credential_ref, null: false
      t.string :contract_version, null: false, default: "1"
      t.uuid :active_deployment_id
      t.bigint :active_sequence, null: false, default: 0
      t.timestamps
    end
    add_foreign_key :publishing_partners, :identity_accounts, column: :owner_id
    add_index :publishing_partners, [ :owner_id, :name ], unique: true
    add_check_constraint :publishing_partners, "active_sequence >= 0", name: "publishing_partner_sequence"

    create_table :publishing_candidates, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :partner_id, null: false
      t.bigint :artifact_blob_id, null: false
      t.string :artifact_sha256, null: false
      t.string :manifest_sha256, null: false
      t.jsonb :manifest, null: false
      t.string :correlation_id, null: false
      t.timestamps
    end
    add_foreign_key :publishing_candidates, :publishing_partners, column: :partner_id
    add_foreign_key :publishing_candidates, :active_storage_blobs, column: :artifact_blob_id
    add_index :publishing_candidates, [ :partner_id, :created_at, :id ]
    add_check_constraint :publishing_candidates, "artifact_sha256 ~ '^[a-f0-9]{64}$' AND manifest_sha256 ~ '^[a-f0-9]{64}$'", name: "publishing_candidate_digests"

    create_table :publishing_validations, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :candidate_id, null: false
      t.string :policy_version, null: false
      t.string :input_fingerprint, null: false
      t.string :state, null: false, default: "pending"
      t.uuid :claim_token
      t.datetime :lease_until
      t.datetime :next_enqueue_at
      t.integer :attempts, null: false, default: 0
      t.jsonb :report, null: false, default: {}
      t.string :last_error
      t.datetime :completed_at
      t.timestamps
    end
    add_foreign_key :publishing_validations, :publishing_candidates, column: :candidate_id
    add_index :publishing_validations, [ :candidate_id, :input_fingerprint ], unique: true, name: "publishing_validation_inputs"
    add_index :publishing_validations, [ :state, :next_enqueue_at ]
    add_check_constraint :publishing_validations, "state IN ('pending','running','passed','rejected','failed') AND attempts >= 0", name: "publishing_validation_state"

    create_table :publishing_deployments, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :partner_id, null: false
      t.uuid :candidate_id, null: false
      t.uuid :validation_id, null: false
      t.uuid :rollback_of_id
      t.string :kind, null: false, default: "publish"
      t.string :state, null: false, default: "pending"
      t.string :scenario, null: false, default: "normal"
      t.string :correlation_id, null: false
      t.uuid :claim_token
      t.datetime :lease_until
      t.datetime :next_enqueue_at
      t.integer :attempts, null: false, default: 0
      t.integer :consecutive_failures, null: false, default: 0
      t.string :last_error
      t.string :remote_id
      t.bigint :remote_sequence
      t.datetime :confirmed_at
      t.timestamps
    end
    add_foreign_key :publishing_deployments, :publishing_partners, column: :partner_id
    add_foreign_key :publishing_deployments, :publishing_candidates, column: :candidate_id
    add_foreign_key :publishing_deployments, :publishing_validations, column: :validation_id
    add_foreign_key :publishing_deployments, :publishing_deployments, column: :rollback_of_id
    add_foreign_key :publishing_partners, :publishing_deployments, column: :active_deployment_id
    add_index :publishing_deployments, :candidate_id, unique: true, where: "kind = 'publish'", name: "publishing_one_publish_per_candidate"
    add_index :publishing_deployments, [ :state, :next_enqueue_at ]
    add_index :publishing_deployments, [ :partner_id, :created_at, :id ]
    add_check_constraint :publishing_deployments, "state IN ('pending','dispatching','unknown','confirmed','failed') AND kind IN ('publish','rollback') AND attempts >= 0 AND consecutive_failures >= 0", name: "publishing_deployment_state"
    add_check_constraint :publishing_deployments, "(kind = 'rollback') = (rollback_of_id IS NOT NULL)", name: "publishing_rollback_basis"

    create_table :publishing_callback_receipts, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :partner_id, null: false
      t.uuid :event_id, null: false
      t.uuid :deployment_id, null: false
      t.string :body_sha256, null: false
      t.timestamps
    end
    add_foreign_key :publishing_callback_receipts, :publishing_partners, column: :partner_id
    add_foreign_key :publishing_callback_receipts, :publishing_deployments, column: :deployment_id
    add_index :publishing_callback_receipts, [ :partner_id, :event_id ], unique: true

    create_table :platform_metric_totals, id: false do |t|
      t.string :name, null: false, primary_key: true
      t.bigint :observations, null: false, default: 0
      t.float :total_seconds, null: false, default: 0
      t.jsonb :buckets, null: false, default: {}
      t.datetime :updated_at, null: false
    end
    add_check_constraint :platform_metric_totals, "observations >= 0 AND total_seconds >= 0", name: "platform_metric_nonnegative"

    reversible do |direction|
      direction.up do
        execute <<~SQL
          CREATE FUNCTION protect_publishing_history() RETURNS trigger LANGUAGE plpgsql AS $$
          BEGIN
            IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'publishing history cannot be deleted'; END IF;
            IF TG_TABLE_NAME = 'publishing_partners' THEN
              IF ROW(NEW.owner_id, NEW.name, NEW.origin, NEW.credential_ref, NEW.contract_version)
                IS DISTINCT FROM ROW(OLD.owner_id, OLD.name, OLD.origin, OLD.credential_ref, OLD.contract_version)
                OR NEW.active_sequence < OLD.active_sequence THEN
                RAISE EXCEPTION 'partner binding and monotonic sequence are protected';
              END IF;
              IF NEW.active_deployment_id IS NOT NULL AND NOT EXISTS (
                SELECT 1 FROM publishing_deployments d WHERE d.id = NEW.active_deployment_id
                  AND d.partner_id = NEW.id AND d.state = 'confirmed' AND d.remote_sequence = NEW.active_sequence
              ) THEN RAISE EXCEPTION 'active deployment must belong to this partner and sequence'; END IF;
            END IF;
            IF TG_TABLE_NAME = 'publishing_candidates'  OR TG_TABLE_NAME = 'publishing_callback_receipts' THEN
              RAISE EXCEPTION 'publishing inputs and receipts are immutable';
            END IF;
            IF TG_TABLE_NAME = 'publishing_validations' THEN
              IF ROW(NEW.candidate_id, NEW.policy_version, NEW.input_fingerprint, NEW.created_at)
                IS DISTINCT FROM ROW(OLD.candidate_id, OLD.policy_version, OLD.input_fingerprint, OLD.created_at)
                OR OLD.state IN ('passed','rejected','failed') THEN
                RAISE EXCEPTION 'validation provenance and terminal result are immutable';
              END IF;
            END IF;
            IF TG_TABLE_NAME = 'publishing_deployments' THEN
              IF ROW(NEW.partner_id, NEW.candidate_id, NEW.validation_id, NEW.rollback_of_id, NEW.kind, NEW.scenario, NEW.correlation_id, NEW.created_at)
                IS DISTINCT FROM ROW(OLD.partner_id, OLD.candidate_id, OLD.validation_id, OLD.rollback_of_id, OLD.kind, OLD.scenario, OLD.correlation_id, OLD.created_at)
                OR OLD.state IN ('confirmed','failed') THEN
                RAISE EXCEPTION 'deployment provenance and terminal result are immutable';
              END IF;
            END IF;
            RETURN NEW;
          END $$;
          CREATE TRIGGER publishing_partner_immutable BEFORE UPDATE OR DELETE ON publishing_partners FOR EACH ROW EXECUTE FUNCTION protect_publishing_history();
          CREATE TRIGGER publishing_candidate_immutable BEFORE UPDATE OR DELETE ON publishing_candidates FOR EACH ROW EXECUTE FUNCTION protect_publishing_history();
          CREATE TRIGGER publishing_validation_immutable BEFORE UPDATE OR DELETE ON publishing_validations FOR EACH ROW EXECUTE FUNCTION protect_publishing_history();
          CREATE TRIGGER publishing_deployment_immutable BEFORE UPDATE OR DELETE ON publishing_deployments FOR EACH ROW EXECUTE FUNCTION protect_publishing_history();
          CREATE TRIGGER publishing_receipt_immutable BEFORE UPDATE OR DELETE ON publishing_callback_receipts FOR EACH ROW EXECUTE FUNCTION protect_publishing_history();
        SQL
      end
      direction.down do
        %w[partner candidate validation deployment receipt].zip(%w[partners candidates validations deployments callback_receipts]).each do |short, table|
          execute "DROP TRIGGER publishing_#{short}_immutable ON publishing_#{table}"
        end
        execute "DROP FUNCTION protect_publishing_history()"
      end
    end
  end
end
