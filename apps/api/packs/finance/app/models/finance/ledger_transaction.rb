module Finance
  class LedgerTransaction < Platform::Record
    self.table_name = "finance_ledger_transactions"
    has_many :entries, class_name: "Finance::LedgerEntry"
  end
end
