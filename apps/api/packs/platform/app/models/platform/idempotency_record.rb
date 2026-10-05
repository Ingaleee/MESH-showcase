module Platform
  class IdempotencyRecord < Record
    self.table_name = "platform_idempotency_records"
  end
end
