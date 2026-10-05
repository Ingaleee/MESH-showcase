class AllowProposalsForNewBriefs < ActiveRecord::Migration[8.1]
  def change
    remove_index :marketplace_proposals, [ :project_id, :creator_id ]
    add_index :marketplace_proposals, [ :project_id, :creator_id, :brief_version ], unique: true, name: "proposal_per_brief"
  end
end
