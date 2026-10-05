class AddStructuredProjectBriefs < ActiveRecord::Migration[8.1]
  def change
    add_column :marketplace_projects, :expected_result, :text, null: false, default: ""
    %i[deliverables requirements skills reference_urls].each do |field|
      add_column :marketplace_projects, field, :text, array: true, null: false, default: []
    end
  end
end
