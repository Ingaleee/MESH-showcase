module Finance
  class Settlement < Platform::Record
    self.table_name = "finance_settlements"
    has_many :payment_operations, class_name: "Finance::PaymentOperation"
  end
end
