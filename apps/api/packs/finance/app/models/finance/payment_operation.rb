module Finance
  class PaymentOperation < Platform::Record
    self.table_name = "finance_payment_operations"
    belongs_to :settlement, class_name: "Finance::Settlement"
    has_many :reconciliation_exceptions, class_name: "Finance::ReconciliationException"
  end
end
