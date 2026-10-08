require "rails_helper"

RSpec.describe "Session cookies on reads", type: :request do
  let(:session_cookie) { "#{Rails.application.config.session_options.fetch(:key)}=" }
  it "keeps ordinary reads from overwriting a later login or logout cookie" do
    client = create(:account)
    sign_in(client)
    project_id = Marketplace::CreateProject.call(actor: client, input: project_input, key: SecureRandom.uuid).fetch(:id)
    [ "/api/v1/projects", "/api/v1/projects/#{project_id}", "/api/v1/creators", "/api/v1/notifications" ].each do |path|
      get path
      expect(response).to have_http_status(:ok)
      expect(response.headers["Set-Cookie"]).to be_nil
    end
    get "/api/v1/operations"
    expect(response).to have_http_status(:forbidden)
    expect(response.headers["Set-Cookie"]).to be_nil
    get "/api/v1/session"
    expect(response.parsed_body.fetch("account").fetch("id")).to eq(client.id)
    expect(response.headers["Set-Cookie"]).to include(session_cookie)
  end

  it "still persists authentication cookies and issues a fresh CSRF token on logout" do
    get "/api/v1/session"
    expect(response).to have_http_status(:ok)
    expect(response.headers["Set-Cookie"]).to include(session_cookie)
    expect(response.parsed_body.fetch("csrf_token")).to be_present
    client = create(:account)
    sign_in(client)
    expect(response.headers["Set-Cookie"]).to include(session_cookie)
    delete "/api/v1/session"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("account")).to be_nil
    expect(response.parsed_body.fetch("csrf_token")).to be_present
    expect(response.headers["Set-Cookie"]).to include(session_cookie)
    get "/api/v1/notifications"
    expect(response).to have_http_status(:unauthorized)
    expect(response.headers["Set-Cookie"]).to be_nil
  end
end
