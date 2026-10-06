require_relative "../config/environment"
require_relative "support/architecture_lab"
require "bcrypt"

ArchitectureLab.guard!
raise "The lab database must be empty" unless Identity::Account.count.zero?
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
connection = Platform::Record.connection
connection.execute("SET statement_timeout = '300000ms'")
# Keep the baseline reproducible after the schema gains the measured indexes.
connection.execute("DROP INDEX IF EXISTS project_title_trigram")
connection.execute("DROP INDEX IF EXISTS project_description_trigram")
password = BCrypt::Password.create("LabPassword2026!", cost: 4)
connection.execute(<<~SQL)
  INSERT INTO identity_accounts (id, email, display_name, password_digest, persona, created_at, updated_at)
  SELECT md5('lab-account-' || i)::uuid, 'person' || i || '@lab.test',
    CASE WHEN i = 19999 THEN 'RareNeedle creator' ELSE 'Creator ' || i END,
    #{connection.quote(password)}, CASE WHEN i = 0 THEN 'client' ELSE 'creator' END,
    TIMESTAMP '2026-01-01' + i * INTERVAL '1 second', TIMESTAMP '2026-01-01'
  FROM generate_series(0, 20000) i;
  INSERT INTO talent_profiles (id, account_id, headline, bio, skills, rate_minor, created_at, updated_at)
  SELECT md5('lab-profile-' || i)::uuid, md5('lab-account-' || i)::uuid,
    CASE WHEN i % 997 = 0 THEN 'RareNeedle brand designer' ELSE 'Independent designer ' || i END,
    repeat('Synthetic portfolio biography. ', 8), ARRAY['Design', 'Typography'], 300000,
    TIMESTAMP '2026-01-01' + i * INTERVAL '1 second', TIMESTAMP '2026-01-01'
  FROM generate_series(1, 20000) i;
  INSERT INTO marketplace_projects (id, client_id, title, category, description, budget_minor, currency, deadline, state, created_at, updated_at)
  SELECT md5('lab-project-' || i)::uuid, md5('lab-account-0')::uuid,
    CASE WHEN i % 997 = 0 THEN 'RareNeedle identity ' || i ELSE 'Synthetic project ' || i END,
    (ARRAY['Тексты','Дизайн','Видео','Разработка','Маркетинг'])[1 + i % 5],
    repeat('A representative synthetic project brief with requirements and deliverables. ', 12),
    10000000, 'RUB', DATE '2027-01-01', CASE WHEN i % 7 = 0 THEN 'closed' ELSE 'open' END,
    TIMESTAMP '2026-01-01' + i * INTERVAL '1 second', TIMESTAMP '2026-01-01'
  FROM generate_series(1, 100000) i;
  INSERT INTO marketplace_proposals (id, project_id, creator_id, brief_version, delivery_days, price_minor, message, created_at, updated_at)
  SELECT md5('lab-proposal-' || i)::uuid, md5('lab-project-' || (1 + (i - 1) % 100000))::uuid,
    md5('lab-account-' || (1 + (i - 1) / 100000))::uuid, 1, 14, 9500000,
    'Synthetic proposal for query-plan measurement', TIMESTAMP '2026-01-01', TIMESTAMP '2026-01-01'
  FROM generate_series(1, 200000) i;
  ANALYZE;
SQL

client = Identity::Account.find_by!(email: "person0@lab.test")
creator = Identity::Account.find_by!(email: "person20000@lab.test")
project = Marketplace::Project.find(Marketplace::CreateProject.call(actor: client, key: "lab-recovery-project", input: {
  title: "Lab versioned file recovery", description: "Restore a private result and its immutable history", category: "Дизайн", budget_minor: 10000000, currency: "RUB", deadline: Date.new(2027, 1, 1)
}).fetch(:id))
proposal = Marketplace::SubmitProposal.call(actor: creator, project: project, key: "lab-proposal", input: { price_minor: 9500000, delivery_days: 18, message: "A recoverable private result", brief_version: 1 })
engagement = Engagements::Engagement.find(Marketplace::AwardProposal.call(actor: client, project: project.reload, proposal_id: proposal.fetch(:id), brief_version: 1, key: "lab-award").fetch(:id))
files = [ [ "identity.pdf", "%PDF-1.4\n" + "versioned identity\n" * 2000 + "%%EOF" ], [ "guidelines.pdf", "%PDF-1.4\n" + "brand guidelines\n" * 1000 + "%%EOF" ] ].map do |name, bytes|
  item = Engagements::WorkFile.create!(engagement: engagement, creator: creator, sha256: Digest::SHA256.hexdigest(bytes))
  item.file.attach(io: StringIO.new(bytes), filename: name, content_type: "application/pdf")
  ScanWorkFileJob.perform_now(item.id)
  raise "Real file scanner did not verify the fixture" unless item.reload.state == "available"
  item
end
submission = Engagements::SubmitWork.call(actor: creator, engagement: engagement.reload, title: "Recoverable identity", content: "Immutable result with two private files", ready_for_acceptance: true, file_ids: files.map(&:id), key: "lab-version")
ArchitectureLab.save_state({ client_id: client.id, creator_id: creator.id, engagement_id: engagement.id, submission_id: submission.fetch(:id), file_ids: files.map(&:id) })
ArchitectureLab.report("dataset", {
  projects: Marketplace::Project.count, profiles: Talent::Profile.count, proposals: Marketplace::Proposal.count,
  accounts: Identity::Account.count, blobs: ActiveStorage::Blob.count,
  seed_seconds: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(2),
  data: "Deterministic synthetic rows inserted in batches with SQL, plus one real business workflow and two files verified by the existing ClamAV. Synthetic rows do not pretend to be complete product history."
})
puts "Architecture dataset prepared in isolated DB: 100000 projects, 20000 profiles, 200000 proposals and a real file workflow."
