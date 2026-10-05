module Platform
  class Error < StandardError
    attr_reader :code, :status, :details

    def initialize(code, message, status: 422, details: {})
      @code, @status, @details = code, status, details
      super(message)
    end
  end
end
