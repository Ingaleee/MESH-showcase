class CreatePublishingUploadIntents < ActiveRecord::Migration[8.1]
  def change
    create_table :publishing_upload_intents, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :partner_id, null: false
      t.string :request_key, null: false, limit: 200
      t.string :fingerprint, null: false
      t.bigint :artifact_blob_id
      t.string :state, null: false, default: "reserved"
      t.uuid :claim_token
      t.datetime :lease_until
      t.jsonb :response
      t.string :last_error
      t.timestamps
    end
    add_foreign_key :publishing_upload_intents, :publishing_partners, column: :partner_id
    add_foreign_key :publishing_upload_intents, :active_storage_blobs, column: :artifact_blob_id
    add_index :publishing_upload_intents, [ :partner_id, :request_key ], unique: true
    add_index :publishing_upload_intents, [ :state, :updated_at ]
    add_index :publishing_upload_intents, :artifact_blob_id, unique: true, where: "artifact_blob_id IS NOT NULL"
    add_check_constraint :publishing_upload_intents,
      "state IN ('reserved','uploading','ready','finalized','discarded') AND fingerprint ~ '^[a-f0-9]{64}$'",
      name: "publishing_upload_state"
    add_check_constraint :publishing_upload_intents,
      "(state <> 'uploading' OR (claim_token IS NOT NULL AND lease_until IS NOT NULL AND artifact_blob_id IS NOT NULL)) AND (state <> 'finalized' OR response IS NOT NULL)",
      name: "publishing_upload_completion"
  end
end
