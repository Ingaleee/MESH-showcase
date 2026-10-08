module WorkflowHelpers
  def project_input
    {
      title: "A careful project", description: "Deliver a clear result and editable sources.", category: "Тексты",
      budget_minor: 100_005, currency: "RUB", deadline: 30.days.from_now.to_date
    }
  end

  def build_workflow
    client = create(:account)
    creator = create(:account, persona: "creator")
    Talent::Profile.create!(account: creator, headline: "Author")
    project_id = Marketplace::CreateProject.call(actor: client, input: project_input, key: SecureRandom.uuid).fetch(:id)
    project = Marketplace::Project.find(project_id)
    proposal_id = Marketplace::SubmitProposal.call(
      actor: creator, project: project, input: { price_minor: 100_005, delivery_days: 7, message: "I can deliver this.", brief_version: 1 }, key: SecureRandom.uuid
    ).fetch(:id)
    engagement_id = Marketplace::AwardProposal.call(actor: client, project: project.reload, proposal_id: proposal_id, brief_version: 1, key: SecureRandom.uuid).fetch(:id)
    [ client, creator, project, Engagements::Engagement.find(engagement_id) ]
  end

  def accept_work(client, creator, engagement)
    submission = Engagements::SubmitWork.call(actor: creator, engagement: engagement.reload, content: "Final work", key: SecureRandom.uuid)
    Engagements::AcceptSubmission.call(actor: client, engagement: engagement.reload, submission_id: submission.fetch(:id), key: SecureRandom.uuid)
  end

  def request_payment(client, engagement, kind: "fund", scenario: "normal")
    result = Finance::RequestOperation.call(actor: client, engagement_id: engagement.id, kind: kind, scenario: scenario, key: SecureRandom.uuid)
    Finance::PaymentOperation.find(result.fetch(:id))
  end

  def confirmed(operation)
    { "key" => operation.id, "id" => "provider-#{operation.id}", "state" => "confirmed", "kind" => operation.kind, "currency" => operation.currency, "amount_minor" => operation.amount_minor }
  end

  def race(*commands)
    ready = Queue.new
    start = Queue.new
    threads = commands.map do |command|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          command.call
        rescue StandardError => error
          error
        end
      end
    end
    commands.length.times { ready.pop }
    commands.length.times { start << true }
    threads.map(&:value)
  end

  def sign_in(account)
    post "/api/v1/session", params: { session: { email: account.email, password: "TestPassword2026!" } }, as: :json
    expect(response).to have_http_status(:ok)
  end
end
