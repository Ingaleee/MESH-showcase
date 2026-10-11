module Platform
  class OutboxEvent < Record
    self.table_name = "platform_outbox_events"
    has_many :deliveries, class_name: "Platform::Delivery", foreign_key: :outbox_event_id
  end
end
