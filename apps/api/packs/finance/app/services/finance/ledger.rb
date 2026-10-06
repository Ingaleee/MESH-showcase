module Finance
  class Ledger
    def self.post!(operation_key:, description:, entries:)
      raise "posting requires a business transaction" unless Platform::Record.connection.transaction_open?
      existing = LedgerTransaction.find_by(operation_key: operation_key)
      return existing if existing
      totals = entries.group_by { |entry| entry.fetch(:currency) }
      unless entries.size >= 2 && totals.values.all? { |rows| rows.sum { |row| row.fetch(:direction) == "debit" ? row.fetch(:amount_minor) : -row.fetch(:amount_minor) }.zero? }
        raise Platform::Error.new("UNBALANCED_LEDGER", "Journal is not balanced.")
      end
      transaction = LedgerTransaction.create!(operation_key: operation_key, description: description)
      entries.each { |entry| LedgerEntry.create!(entry.merge(ledger_transaction_id: transaction.id)) }
      transaction.update!(status: "posted")
      transaction
    end
  end
end
