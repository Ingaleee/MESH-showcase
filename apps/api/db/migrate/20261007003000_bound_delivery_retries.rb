class BoundDeliveryRetries < ActiveRecord::Migration[8.1]
  def change
    add_column :platform_deliveries, :failure_count, :integer, null: false, default: 0
    add_column :platform_deliveries, :available_at, :datetime
    add_index :platform_deliveries, [ :state, :available_at ]
  end
end
