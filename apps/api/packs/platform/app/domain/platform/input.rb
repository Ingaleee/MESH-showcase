module Platform
  class Input
    def self.integer(value)
      return value if value.is_a?(Integer)
      return Integer(value, 10) if value.is_a?(String) && value.match?(/\A-?\d+\z/)

      raise ArgumentError, "Expected an integer input."
    end
  end
end
