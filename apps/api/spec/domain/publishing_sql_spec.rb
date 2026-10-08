require "rails_helper"

RSpec.describe "Publishing SQL invariants" do
  it "rejects a confirmed deployment with a NULL sequence independently of model validation" do
    operator, _, candidate, validation = publishing_candidate
    passed_validation(validation)
    deployment = deployment_for(operator, candidate, validation)
    expect {
      deployment.update_columns(state: "confirmed", remote_id: "remote-1", confirmed_at: Time.current, remote_sequence: nil)
    }.to raise_error(ActiveRecord::StatementInvalid, /publishing_confirmed_identity/)
    expect(deployment.reload.state).to eq("pending")
  end

  it "rejects clearing the active reference, sequence regression and a foreign deployment" do
    operator, partner, candidate, validation = publishing_candidate
    passed_validation(validation)
    deployment = deployment_for(operator, candidate, validation)
    Publishing::ApplyObservation.call(deployment: deployment, observation: published_observation(deployment))
    expect { partner.reload.update_columns(active_deployment_id: nil) }.to raise_error(ActiveRecord::StatementInvalid)
    expect { partner.reload.update_columns(active_sequence: 0) }.to raise_error(ActiveRecord::StatementInvalid)
    other_operator, other_partner, other_candidate, other_validation = publishing_candidate
    passed_validation(other_validation)
    other_deployment = deployment_for(other_operator, other_candidate, other_validation)
    Publishing::ApplyObservation.call(deployment: other_deployment, observation: published_observation(other_deployment, sequence: 2))
    expect {
      partner.reload.update_columns(active_deployment_id: other_deployment.id, active_sequence: 2)
    }.to raise_error(ActiveRecord::StatementInvalid, /active deployment/)
    expect(partner.reload.active_deployment_id).to eq(deployment.id)
    expect(other_partner.reload.active_deployment_id).to eq(other_deployment.id)
  end

  it "checks active state on raw INSERT as well as UPDATE" do
    operator, _, _, _ = publishing_candidate
    connection = Platform::Record.connection
    expect {
      connection.execute(<<~SQL)
        INSERT INTO publishing_partners (id, owner_id, name, origin, credential_ref, contract_version,
          active_sequence, created_at, updated_at)
        VALUES (gen_random_uuid(), #{connection.quote(operator.id)}, 'Invalid initial state',
          'http://partner:3216', 'SHOWCASE', '1', 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      SQL
    }.to raise_error(ActiveRecord::StatementInvalid, /publishing_active_presence/)
  end

  it "rejects rollback of an unconfirmed deployment through SQL and accepts a valid basis" do
    operator, partner, candidate, validation = publishing_candidate
    passed_validation(validation)
    basis = deployment_for(operator, candidate, validation)
    values = { partner: partner, candidate: candidate, validation: validation, kind: "rollback",
      rollback_of_id: basis.id, correlation_id: SecureRandom.uuid }
    expect { Publishing::Deployment.create!(values) }.to raise_error(ActiveRecord::StatementInvalid, /rollback requires/)
    Publishing::ApplyObservation.call(deployment: basis, observation: published_observation(basis))
    expect(Publishing::Deployment.create!(values).state).to eq("pending")
    expect { basis.destroy! }.to raise_error(ActiveRecord::StatementInvalid, /cannot be deleted/)
  end
end
