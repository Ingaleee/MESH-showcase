FactoryBot.define do
  factory :account, class: "Identity::Account" do
    sequence(:email) { |number| "person-#{number}@mesh.test" }
    display_name { "Test Person" }
    password { "TestPassword2026!" }
    persona { "client" }
  end
end
