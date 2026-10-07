require "rails_helper"

RSpec.describe "Public creator directory", type: :request do
  it "finds authors by display name, specialization and skills without publishing private account fields" do
    named = create(:account, persona: "creator", display_name: "Марк Соколов")
    profile = Talent::Profile.create!(account: named, headline: "Бренд-дизайнер", skills: [ "Figma", "Айдентика" ])
    Talent::Profile.create!(account: create(:account, persona: "creator", display_name: "Другой автор"), headline: "Редактор")

    [ "марк", "дизайнер", "Figma" ].each do |query|
      get "/api/v1/creators", params: { q: query }
      expect(response).to have_http_status(:ok)
      results = response.parsed_body.fetch("data")
      expect(results.map { |item| item.fetch("id") }).to eq([ profile.id ])
      expect(results.first.fetch("account")).not_to include("email", "operator", "password_digest")
    end
  end

  it "treats SQL wildcard characters in a person's name as literal search text" do
    named = create(:account, persona: "creator", display_name: "Студия 100%_Ready")
    profile = Talent::Profile.create!(account: named, headline: "Дизайнер")
    Talent::Profile.create!(account: create(:account, persona: "creator", display_name: "Студия 100XYReady"), headline: "Дизайнер")

    get "/api/v1/creators", params: { q: "100%_" }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("data").map { |item| item.fetch("id") }).to eq([ profile.id ])
  end
end
