require "rails_helper"

RSpec.describe Marketplace::SearchProjects do
  it "walks timestamp ties without duplicates, skipped rows or a newly inserted newer project" do
    client = create(:account)
    time = Time.utc(2026, 1, 1, 12)
    5.times do |number|
      Marketplace::Project.create!(project_input.merge(client: client, title: "Project #{number}", created_at: time))
    end
    Marketplace::Project.create!(project_input.merge(client: client, title: "Private closed", state: "closed", created_at: time))
    expected = Marketplace::Project.where(state: "open").order(created_at: :desc, id: :desc).pluck(:id)
    first = described_class.call(actor: nil, limit: 2)
    newer = Marketplace::Project.create!(project_input.merge(client: client, title: "Published later", created_at: time + 1))
    ids = first.fetch(:records).map(&:id)
    cursor = first.fetch(:next_cursor)
    while cursor
      page = described_class.call(actor: nil, limit: 2, cursor: cursor)
      ids.concat(page.fetch(:records).map(&:id))
      cursor = page.fetch(:next_cursor)
    end
    expect(ids).to eq(expected)
    expect(ids).not_to include(newer.id)
  end

  it "rejects cursor reuse for another actor or filter and rejects a tampered signature" do
    client = create(:account)
    2.times { |number| Marketplace::Project.create!(project_input.merge(client: client, title: "Project #{number}")) }
    cursor = described_class.call(actor: nil, limit: 1).fetch(:next_cursor)
    [ { actor: client, cursor: cursor }, { actor: nil, query: "Project", cursor: cursor }, { actor: nil, cursor: "#{cursor}tampered" } ].each do |input|
      expect { described_class.call(**input) }.to raise_error(Platform::Error) { |error| expect(error.code).to eq("INVALID_CURSOR") }
    end
  end
end
