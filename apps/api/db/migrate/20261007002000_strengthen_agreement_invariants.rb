class StrengthenAgreementInvariants < ActiveRecord::Migration[8.1]
  def up
    add_index :engagements_submissions, [ :id, :engagement_id ], unique: true
    execute <<~SQL
      ALTER TABLE engagements_acceptances ADD CONSTRAINT acceptance_matches_engagement
        FOREIGN KEY (submission_id, engagement_id) REFERENCES engagements_submissions(id, engagement_id);
      CREATE FUNCTION mesh_protect_agreement_terms() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF NEW.terms IS DISTINCT FROM OLD.terms
          OR NEW.client_id <> OLD.client_id OR NEW.creator_id <> OLD.creator_id
          OR NEW.source_award_id <> OLD.source_award_id THEN
          RAISE EXCEPTION 'agreed terms and parties are immutable';
        END IF;
        RETURN NEW;
      END $$;
      CREATE TRIGGER agreement_terms_immutable BEFORE UPDATE ON engagements_engagements
        FOR EACH ROW EXECUTE FUNCTION mesh_protect_agreement_terms();
    SQL
    add_column :finance_webhook_receipts, :next_enqueue_at, :datetime
    add_index :finance_webhook_receipts, [ :processed_at, :next_enqueue_at ]
    add_check_constraint :finance_payment_operations, "amount_minor > 0 AND currency IN ('RUB','USD','EUR','JPY')", name: "payment_money_valid"
  end

  def down
    remove_check_constraint :finance_payment_operations, name: "payment_money_valid"
    remove_index :finance_webhook_receipts, [ :processed_at, :next_enqueue_at ]
    remove_column :finance_webhook_receipts, :next_enqueue_at
    execute "DROP TRIGGER agreement_terms_immutable ON engagements_engagements"
    execute "DROP FUNCTION mesh_protect_agreement_terms()"
    execute "ALTER TABLE engagements_acceptances DROP CONSTRAINT acceptance_matches_engagement"
    remove_index :engagements_submissions, [ :id, :engagement_id ]
  end
end
