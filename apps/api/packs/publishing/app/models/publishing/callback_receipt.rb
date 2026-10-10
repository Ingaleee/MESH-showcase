module Publishing
  class CallbackReceipt < Platform::Record
    self.table_name = "publishing_callback_receipts"
    belongs_to :partner, class_name: "Publishing::Partner"
    belongs_to :deployment, class_name: "Publishing::Deployment"
  end
end
