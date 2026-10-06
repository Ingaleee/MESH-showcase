class ProtectLedgerAndHistory < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE FUNCTION mesh_check_ledger_balance() RETURNS trigger LANGUAGE plpgsql AS $$
      DECLARE target_id uuid; entry_count integer;
      BEGIN
        IF TG_TABLE_NAME = 'finance_ledger_transactions' THEN
          target_id := NEW.id;
        ELSE
          target_id := COALESCE(NEW.ledger_transaction_id, OLD.ledger_transaction_id);
        END IF;
        IF EXISTS (SELECT 1 FROM finance_ledger_transactions WHERE id = target_id AND status = 'posted') THEN
          SELECT COUNT(*) INTO entry_count FROM finance_ledger_entries WHERE ledger_transaction_id = target_id;
          IF entry_count < 2 OR EXISTS (
            SELECT currency FROM finance_ledger_entries WHERE ledger_transaction_id = target_id
            GROUP BY currency HAVING SUM(CASE direction WHEN 'debit' THEN amount_minor ELSE -amount_minor END) <> 0
          ) THEN RAISE EXCEPTION 'unbalanced ledger transaction %', target_id; END IF;
        END IF;
        RETURN NULL;
      END $$;
      CREATE CONSTRAINT TRIGGER ledger_header_balance AFTER INSERT OR UPDATE ON finance_ledger_transactions
        DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION mesh_check_ledger_balance();
      CREATE CONSTRAINT TRIGGER ledger_entry_balance AFTER INSERT OR UPDATE OR DELETE ON finance_ledger_entries
        DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION mesh_check_ledger_balance();
      CREATE FUNCTION mesh_protect_posted_ledger() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF TG_TABLE_NAME = 'finance_ledger_transactions' THEN
          IF OLD.status = 'posted' THEN RAISE EXCEPTION 'posted ledger transaction is immutable'; END IF;
        ELSIF TG_OP = 'INSERT' THEN
          IF EXISTS (SELECT 1 FROM finance_ledger_transactions WHERE id = NEW.ledger_transaction_id AND status = 'posted') THEN
            RAISE EXCEPTION 'posted ledger entries are immutable';
          END IF;
          RETURN NEW;
        ELSE
          IF EXISTS (SELECT 1 FROM finance_ledger_transactions WHERE id IN (OLD.ledger_transaction_id, NEW.ledger_transaction_id) AND status = 'posted') THEN
            RAISE EXCEPTION 'posted ledger entries are immutable';
          END IF;
        END IF;
        IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
        RETURN NEW;
      END $$;
      CREATE TRIGGER ledger_header_immutable BEFORE UPDATE OR DELETE ON finance_ledger_transactions
        FOR EACH ROW EXECUTE FUNCTION mesh_protect_posted_ledger();
      CREATE TRIGGER ledger_entries_immutable BEFORE INSERT OR UPDATE OR DELETE ON finance_ledger_entries
        FOR EACH ROW EXECUTE FUNCTION mesh_protect_posted_ledger();
      CREATE FUNCTION mesh_protect_history() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN RAISE EXCEPTION 'historical record is immutable'; END $$;
      CREATE TRIGGER submission_immutable BEFORE UPDATE OR DELETE ON engagements_submissions
        FOR EACH ROW EXECUTE FUNCTION mesh_protect_history();
      CREATE TRIGGER brief_immutable BEFORE UPDATE OR DELETE ON marketplace_brief_versions
        FOR EACH ROW EXECUTE FUNCTION mesh_protect_history();
      CREATE TRIGGER acceptance_immutable BEFORE UPDATE OR DELETE ON engagements_acceptances
        FOR EACH ROW EXECUTE FUNCTION mesh_protect_history();
      CREATE TRIGGER audit_immutable BEFORE UPDATE OR DELETE ON platform_audit_entries
        FOR EACH ROW EXECUTE FUNCTION mesh_protect_history();
    SQL
  end

  def down
    execute "DROP FUNCTION mesh_check_ledger_balance() CASCADE"
    execute "DROP FUNCTION mesh_protect_posted_ledger() CASCADE"
    execute "DROP FUNCTION mesh_protect_history() CASCADE"
  end
end
