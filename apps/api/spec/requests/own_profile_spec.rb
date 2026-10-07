require "rails_helper"

RSpec.describe "Author profile lookup", type: :request do
  it "returns the current author's profile outside the capped public directory and requires a session" do
    40.times { Talent::Profile.create!(account: create(:account, persona: "creator"), headline: "Other designer") }
    account = create(:account, persona: "creator")
    profile = Talent::Profile.create!(account: account, headline: "My specialization")
    expect(Talent::Directory.search.map(&:id)).not_to include(profile.id)
    get "/api/v1/creators/mine"
    expect(response).to have_http_status(:unauthorized)
    sign_in(account)
    get "/api/v1/creators/mine"
    expect(response.parsed_body.fetch("profile")).to include("id" => profile.id, "account_id" => account.id)
    expect(response.body).not_to include("Other designer", account.email)
    sign_in(create(:account))
    get "/api/v1/creators/mine"
    expect(response.parsed_body).to eq("profile" => nil)
  end
end
