module Platform
  class Current < ActiveSupport::CurrentAttributes
    attribute :actor_id, :correlation_id
  end
end
