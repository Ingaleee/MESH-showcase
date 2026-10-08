class StrengthenPublishingStates < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :publishing_deployments, name: "publishing_confirmed_identity"
    add_check_constraint :publishing_deployments,
      "state <> 'confirmed' OR (remote_id IS NOT NULL AND remote_id <> '' AND remote_sequence IS NOT NULL AND remote_sequence > 0 AND confirmed_at IS NOT NULL)",
      name: "publishing_confirmed_identity"
    add_check_constraint :publishing_partners,
      "(active_deployment_id IS NULL AND active_sequence = 0) OR (active_deployment_id IS NOT NULL AND active_sequence > 0)",
      name: "publishing_active_presence"
    execute <<~SQL
      CREATE FUNCTION enforce_publishing_active_binding() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF NEW.active_deployment_id IS NOT NULL AND NOT EXISTS (
          SELECT 1 FROM publishing_deployments d WHERE d.id = NEW.active_deployment_id
            AND d.partner_id = NEW.id AND d.state = 'confirmed' AND d.remote_sequence = NEW.active_sequence
        ) THEN RAISE EXCEPTION 'active deployment must belong to this partner and sequence'; END IF;
        RETURN NEW;
      END $$;
      CREATE TRIGGER publishing_active_binding BEFORE INSERT OR UPDATE ON publishing_partners
        FOR EACH ROW EXECUTE FUNCTION enforce_publishing_active_binding();
      CREATE FUNCTION enforce_publishing_rollback_basis() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF NEW.kind = 'rollback' AND NOT EXISTS (
          SELECT 1 FROM publishing_deployments d WHERE d.id = NEW.rollback_of_id
            AND d.partner_id = NEW.partner_id AND d.candidate_id = NEW.candidate_id AND d.state = 'confirmed'
        ) THEN RAISE EXCEPTION 'rollback requires a confirmed deployment of the same partner and candidate'; END IF;
        RETURN NEW;
      END $$;
      CREATE TRIGGER publishing_rollback_basis BEFORE INSERT ON publishing_deployments
        FOR EACH ROW EXECUTE FUNCTION enforce_publishing_rollback_basis();
    SQL
  end

  def down
    execute "DROP TRIGGER publishing_rollback_basis ON publishing_deployments"
    execute "DROP FUNCTION enforce_publishing_rollback_basis()"
    execute "DROP TRIGGER publishing_active_binding ON publishing_partners"
    execute "DROP FUNCTION enforce_publishing_active_binding()"
    remove_check_constraint :publishing_partners, name: "publishing_active_presence"
    remove_check_constraint :publishing_deployments, name: "publishing_confirmed_identity"
    add_check_constraint :publishing_deployments,
      "state <> 'confirmed' OR (remote_id IS NOT NULL AND remote_sequence > 0 AND confirmed_at IS NOT NULL)",
      name: "publishing_confirmed_identity"
  end
end
