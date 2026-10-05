class AddProjectIntakeControl < ActiveRecord::Migration[8.1]
  def change
    add_column :marketplace_projects, :accepting_proposals, :boolean, null: false, default: true
  end
end
