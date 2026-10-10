require "rails_helper"

RSpec.describe Platform::RateLimiter do
  include ActiveSupport::Testing::TimeHelpers

  def consume(identity = "198.51.100.20", limit: 1)
    described_class.consume(scope: "authentication", identity: identity, limit: limit, period: 3.minutes)
  end

  it "shares a single budget across independent PostgreSQL connections" do
    results = race(-> { consume }, -> { consume })
    expect(results.map(&:allowed)).to contain_exactly(true, false)
    expect(Platform::RateLimitBucket.sole.attempts).to eq(2)
    expect(Platform::RateLimitBucket.sole.key_digest).to match(/\A[0-9a-f]{64}\z/)
    expect(Platform::RateLimitBucket.sole.key_digest).not_to include("198.51.100.20")
  end

  it "does not extend the window on blocked requests and restores the budget at expiry" do
    travel_to Time.current do
      expect(consume.allowed).to be(true)
      expiry = Platform::RateLimitBucket.sole.expires_at
      travel 1.minute
      blocked = consume
      expect(blocked.allowed).to be(false)
      expect(blocked.retry_after).to eq(120)
      expect(Platform::RateLimitBucket.sole.expires_at).to eq(expiry)
      travel 2.minutes
      expect(consume.allowed).to be(true)
      expect(consume("198.51.100.21").allowed).to be(true)
    end
  end

  it "removes only long-expired buckets in a bounded batch" do
    2.times { consume }
    retained = Platform::RateLimitBucket.sole.key_digest
    Platform::RateLimitBucket.insert_all!((1..1001).map { |index| { key_digest: "expired-#{index}", attempts: 1, expires_at: 2.days.ago } })
    expect(described_class.purge_expired).to eq(1000)
    expect(Platform::RateLimitBucket.exists?(retained)).to be(true)
    expect(Platform::RateLimitBucket.count).to eq(2)
  end
end
