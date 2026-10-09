class IndexBoundedProjectReads < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :marketplace_proposals, [ :project_id, :created_at, :id ], order: { created_at: :desc, id: :desc }, name: "proposals_recent_page", algorithm: :concurrently
    add_index :marketplace_proposals, [ :project_id, :price_minor, :created_at, :id ], order: { created_at: :desc, id: :desc }, name: "proposals_price_page", algorithm: :concurrently
    add_index :marketplace_proposals, [ :project_id, :delivery_days, :created_at, :id ], order: { created_at: :desc, id: :desc }, name: "proposals_days_page", algorithm: :concurrently
    add_index :engagements_feedback, [ :engagement_id, :created_at, :id ], order: { created_at: :desc, id: :desc }, name: "feedback_recent_page", algorithm: :concurrently
  end
end
