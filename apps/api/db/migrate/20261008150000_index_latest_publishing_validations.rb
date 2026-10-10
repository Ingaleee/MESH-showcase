class IndexLatestPublishingValidations < ActiveRecord::Migration[8.1]
  def change
    add_index :publishing_validations, [ :candidate_id, :created_at, :id ],
      order: { created_at: :desc, id: :desc }, name: "publishing_latest_validation"
  end
end
