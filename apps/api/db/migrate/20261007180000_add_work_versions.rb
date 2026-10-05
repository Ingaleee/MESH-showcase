class AddWorkVersions < ActiveRecord::Migration[8.1]
  def change
    add_column :engagements_engagements, :started_at, :datetime
    add_column :engagements_submissions, :title, :string, null: false, default: ""
    add_column :engagements_submissions, :ready_for_acceptance, :boolean, null: false, default: true
    add_column :engagements_submissions, :files_manifest, :jsonb, null: false, default: []
    add_column :engagements_submissions, :manifest_sha256, :string
    create_table :engagements_work_files, id: :uuid do |t|
      t.references :engagement, type: :uuid, null: false, foreign_key: { to_table: :engagements_engagements }
      t.references :creator, type: :uuid, null: false, foreign_key: { to_table: :identity_accounts }
      t.references :submission, type: :uuid, foreign_key: { to_table: :engagements_submissions }
      t.string :sha256, null: false
      t.string :state, null: false, default: "quarantined"
      t.string :scan_error
      t.timestamps
    end
    add_check_constraint :engagements_work_files, "state IN ('quarantined','available','rejected')", name: "work_file_state"
    create_table :engagements_feedback, id: :uuid do |t|
      t.references :engagement, type: :uuid, null: false, foreign_key: { to_table: :engagements_engagements }
      t.references :submission, type: :uuid, foreign_key: { to_table: :engagements_submissions }
      t.references :actor, type: :uuid, null: false, foreign_key: { to_table: :identity_accounts }
      t.string :kind, null: false, default: "comment"
      t.text :content, null: false
      t.timestamps
    end
    add_check_constraint :engagements_feedback, "kind IN ('comment','changes_requested')", name: "work_feedback_kind"
    add_index :engagements_feedback, :submission_id, unique: true, where: "kind = 'changes_requested'", name: "one_changes_request_per_submission"
    reversible do |direction|
      direction.up do
        execute <<~SQL
          ALTER TABLE engagements_work_files ADD CONSTRAINT work_file_matches_engagement
            FOREIGN KEY (submission_id, engagement_id) REFERENCES engagements_submissions(id, engagement_id);
          ALTER TABLE engagements_feedback ADD CONSTRAINT feedback_matches_engagement
            FOREIGN KEY (submission_id, engagement_id) REFERENCES engagements_submissions(id, engagement_id);
          CREATE TRIGGER feedback_immutable BEFORE UPDATE OR DELETE ON engagements_feedback
            FOR EACH ROW EXECUTE FUNCTION mesh_protect_history();
          CREATE FUNCTION mesh_protect_work_file() RETURNS trigger LANGUAGE plpgsql AS $$
          BEGIN
            IF OLD.submission_id IS NOT NULL AND (TG_OP = 'DELETE' OR
              NEW.submission_id IS DISTINCT FROM OLD.submission_id OR
              NEW.engagement_id IS DISTINCT FROM OLD.engagement_id OR
              NEW.creator_id IS DISTINCT FROM OLD.creator_id OR NEW.sha256 IS DISTINCT FROM OLD.sha256) THEN
              RAISE EXCEPTION 'submitted file association is immutable';
            END IF;
            IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
            RETURN NEW;
          END $$;
          CREATE TRIGGER work_file_immutable BEFORE UPDATE OR DELETE ON engagements_work_files
            FOR EACH ROW EXECUTE FUNCTION mesh_protect_work_file();
        SQL
      end
      direction.down do
        execute "DROP TRIGGER work_file_immutable ON engagements_work_files; DROP FUNCTION mesh_protect_work_file(); DROP TRIGGER feedback_immutable ON engagements_feedback;"
      end
    end
  end
end
