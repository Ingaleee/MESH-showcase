module Finance
  class ReconciliationException < Platform::Record
    self.table_name = "finance_reconciliation_exceptions"
  end
end
