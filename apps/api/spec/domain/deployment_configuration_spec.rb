require "rails_helper"

RSpec.describe Api::DeploymentConfiguration do
  let(:environment) do
    { "MESH_PUBLIC_ORIGIN" => "https://mesh.example.test" }.merge(described_class::SECRETS.to_h { |name, _| [ name, SecureRandom.hex(32) ] })
  end

  it "accepts a valid HTTPS origin and separate secrets" do
    expect(described_class.validate!(environment)).to be(true)
  end

  it "rejects demo, missing, short and reused secrets without exposing their values" do
    [ nil, "short", "local-sandbox-only-change-for-deployment" ].each do |secret|
      invalid = environment.merge("MESH_GATEWAY_SECRET" => secret).compact
      expect { described_class.validate!(invalid) }.to raise_error(ArgumentError, /MESH_GATEWAY_SECRET/)
    end
    invalid = environment.merge("MESH_GATEWAY_SECRET" => environment.fetch("MESH_WEBHOOK_SECRET"))
    expect { described_class.validate!(invalid) }.to raise_error(ArgumentError, /different for each purpose/)
  end

  it "rejects credentials, paths, query strings, fragments and non-HTTPS origins" do
    [ "http://mesh.test", "https://user:secret@mesh.test", "https://mesh.test/project", "https://mesh.test?key=private", "https://mesh.test#fragment", "https://" ].each do |origin|
      expect { described_class.validate!(environment.merge("MESH_PUBLIC_ORIGIN" => origin)) }.to raise_error(ArgumentError)
    end
  end
end
