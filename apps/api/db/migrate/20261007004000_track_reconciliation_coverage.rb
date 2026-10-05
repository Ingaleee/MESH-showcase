class TrackReconciliationCoverage < ActiveRecord::Migration[8.1]
  def change
    add_column :finance_payment_operations, :reconciled_at, :datetime
    add_index :finance_payment_operations, [ :reconciled_at, :created_at ]
  end
end
