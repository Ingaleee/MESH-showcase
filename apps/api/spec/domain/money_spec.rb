require "rails_helper"

RSpec.describe Platform::Money do
  it "uses integer half-up rounding at the boundary" do
    expect(described_class.new(minor: 100_005, currency: "RUB").commission(basis_points: 1000).minor).to eq(10_001)
    expect(described_class.new(minor: 4, currency: "JPY").commission(basis_points: 1000).minor).to eq(0)
    expect(described_class.new(minor: 5, currency: "JPY").commission(basis_points: 1000).minor).to eq(1)
  end

  it "conserves gross = fee + net for 2000 reproducible generated amounts" do
    random = Random.new(20261007)
    2000.times do
      gross = described_class.new(minor: random.rand(1..100_000_000_000), currency: %w[RUB USD EUR JPY].sample(random: random))
      fee = gross.commission(basis_points: random.rand(0..10_000))
      net = gross - fee
      expect((net + fee).minor).to eq(gross.minor)
      expect(fee.minor).to be_between(0, gross.minor)
      expect(gross).to be_frozen
    end
  end

  it "rejects floats, mixed currencies, unsupported currencies and fractional basis points" do
    expect { described_class.new(minor: 1.5, currency: "RUB") }.to raise_error(ArgumentError)
    expect { described_class.new(minor: 1, currency: "BTC") }.to raise_error(ArgumentError)
    money = described_class.new(minor: 100, currency: "RUB")
    expect { money + described_class.new(minor: 100, currency: "USD") }.to raise_error(ArgumentError)
    expect { money.commission(basis_points: 1.5) }.to raise_error(ArgumentError)
  end
end
