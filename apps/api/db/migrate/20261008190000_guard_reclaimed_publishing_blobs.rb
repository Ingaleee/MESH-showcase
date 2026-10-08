class GuardReclaimedPublishingBlobs < ActiveRecord::Migration[8.1]
  def up
    %w[candidate attachment].each do |kind|
      table, column = kind == "candidate" ? [ "publishing_candidates", "artifact_blob_id" ] : [ "active_storage_attachments", "blob_id" ]
      execute <<~SQL
        CREATE FUNCTION guard_reclaimed_publishing_#{kind}() RETURNS trigger LANGUAGE plpgsql AS $$
        DECLARE upload_state text;
        BEGIN
          SELECT state INTO upload_state FROM publishing_upload_intents
            WHERE artifact_blob_id = NEW.#{column} FOR UPDATE;
          IF upload_state = 'discarded' THEN
            RAISE EXCEPTION 'a reclaimed publishing blob cannot acquire references';
          END IF;
          RETURN NEW;
        END $$;
        CREATE TRIGGER publishing_reclaimed_#{kind} BEFORE INSERT OR UPDATE ON #{table}
          FOR EACH ROW EXECUTE FUNCTION guard_reclaimed_publishing_#{kind}();
      SQL
    end
  end

  def down
    execute <<~SQL
      DROP TRIGGER publishing_reclaimed_candidate ON publishing_candidates;
      DROP TRIGGER publishing_reclaimed_attachment ON active_storage_attachments;
      DROP FUNCTION guard_reclaimed_publishing_candidate();
      DROP FUNCTION guard_reclaimed_publishing_attachment();
    SQL
  end
end
