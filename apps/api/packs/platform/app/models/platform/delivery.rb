module Platform
  class Delivery < Record
    self.table_name = "platform_deliveries"
    belongs_to :outbox_event, class_name: "Platform::OutboxEvent"
  end
end
