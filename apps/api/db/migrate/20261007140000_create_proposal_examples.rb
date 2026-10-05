class CreateProposalExamples < ActiveRecord::Migration[8.1]
  def change
    create_table :marketplace_proposal_examples, id: :uuid do |t|
      t.references :project, type: :uuid, null: false, foreign_key: { to_table: :marketplace_projects }
      t.references :creator, type: :uuid, null: false, foreign_key: { to_table: :identity_accounts }
      t.references :proposal, type: :uuid, foreign_key: { to_table: :marketplace_proposals }, index: { unique: true }
      t.string :state, null: false, default: "quarantined"
      t.string :sha256, null: false
      t.string :scan_error
      t.timestamps
    end
    add_check_constraint :marketplace_proposal_examples, "state IN ('quarantined', 'available', 'rejected')", name: "proposal_example_state"
  end
end
