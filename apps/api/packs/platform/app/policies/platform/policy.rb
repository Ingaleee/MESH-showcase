module Platform
  class Policy
    attr_reader :actor, :record
    def initialize(actor, record)
      @actor, @record = actor, record
    end
    def authenticated?
      !actor.nil?
    end
    def operator?
      actor&.operator?
    end
  end
end
