class BindPublishingProvenance < ActiveRecord::Migration[8.1]
  def change
    add_index :publishing_candidates, [ :id, :partner_id ], unique: true
    add_index :publishing_validations, [ :id, :candidate_id ], unique: true
    add_index :publishing_deployments, [ :id, :partner_id ], unique: true
    add_foreign_key :publishing_deployments, :publishing_candidates, column: [ :candidate_id, :partner_id ], primary_key: [ :id, :partner_id ]
    add_foreign_key :publishing_deployments, :publishing_validations, column: [ :validation_id, :candidate_id ], primary_key: [ :id, :candidate_id ]
    add_foreign_key :publishing_callback_receipts, :publishing_deployments, column: [ :deployment_id, :partner_id ], primary_key: [ :id, :partner_id ]
    add_index :publishing_deployments, [ :partner_id, :remote_sequence ], unique: true, where: "remote_sequence IS NOT NULL", name: "publishing_remote_sequence_unique"
    add_check_constraint :publishing_validations, "state NOT IN ('passed','rejected') OR (completed_at IS NOT NULL AND report ? 'checks')", name: "publishing_completed_validation"
    add_check_constraint :publishing_deployments, "state <> 'confirmed' OR (remote_id IS NOT NULL AND remote_sequence > 0 AND confirmed_at IS NOT NULL)", name: "publishing_confirmed_identity"
    reversible do |direction|
      direction.up do
        execute <<~SQL
          CREATE FUNCTION validate_publishing_release_basis() RETURNS trigger LANGUAGE plpgsql AS $$
          BEGIN
            IF NOT EXISTS (SELECT 1 FROM publishing_validations v WHERE v.id = NEW.validation_id
              AND v.candidate_id = NEW.candidate_id AND v.state = 'passed') THEN
              RAISE EXCEPTION 'release requires a passed validation of this candidate';
            END IF;
            RETURN NEW;
          END $$;
          CREATE TRIGGER publishing_release_basis BEFORE INSERT ON publishing_deployments
            FOR EACH ROW EXECUTE FUNCTION validate_publishing_release_basis();
        SQL
      end
      direction.down do
        execute "DROP TRIGGER publishing_release_basis ON publishing_deployments"
        execute "DROP FUNCTION validate_publishing_release_basis()"
      end
    end
  end
end
