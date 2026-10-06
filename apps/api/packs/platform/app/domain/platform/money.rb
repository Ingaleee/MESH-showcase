module Platform
  class Money
    CURRENCIES = { "RUB" => 2, "USD" => 2, "EUR" => 2, "JPY" => 0 }.freeze
    attr_reader :minor, :currency

    def initialize(minor:, currency:)
      raise ArgumentError, "amount must be an integer" unless minor.is_a?(Integer)
      raise ArgumentError, "unsupported currency" unless CURRENCIES.key?(currency)
      @minor, @currency = minor, currency
      freeze
    end

    def +(other)
      check_currency!(other)
      self.class.new(minor: minor + other.minor, currency: currency)
    end

    def -(other)
      check_currency!(other)
      self.class.new(minor: minor - other.minor, currency: currency)
    end

    # Half-up, integer-only; policy v1 is fixed at agreement creation.
    def commission(basis_points:)
      raise ArgumentError, "invalid commission" unless basis_points.is_a?(Integer) && basis_points.between?(0, 10_000)
      self.class.new(minor: (minor * basis_points + 5_000).div(10_000), currency: currency)
    end

    private

    def check_currency!(other)
      raise ArgumentError, "currency mismatch" unless currency == other.currency
    end
  end
end
