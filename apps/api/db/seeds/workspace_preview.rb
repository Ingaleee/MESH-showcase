require "digest"

client = Identity::Account.find_by!(email: "client@mesh.local")
creator = Identity::Account.find_by!(email: "design@mesh.local")
marker = Platform::IdempotencyRecord.find_by(actor_id: client.id, operation: "create_project", key: "demo-workroom-v1")
project = if marker
  Marketplace::Project.find(marker.response.fetch("id"))
else
  source = Marketplace::Project.find_by!(title: "Айдентика для кофейного бренда", client_id: client.id)
  input = source.brief_snapshot.except("brief_version").symbolize_keys.merge(title: "NORA — айдентика кофейного бренда", deadline: 21.days.from_now.to_date)
  Platform::Current.set(actor_id: client.id, correlation_id: SecureRandom.uuid) do
    Marketplace::Project.find(Marketplace::CreateProject.call(actor: client, input: input, key: "demo-workroom-v1").fetch(:id))
  end
end
unless Marketplace::Award.exists?(project_id: project.id)
  proposal = Marketplace::SubmitProposal.call(actor: creator, project: project, input: { price_minor: 9500000, delivery_days: 18, message: "Разработаю визуальную систему NORA, упаковку и гайдлайн.", brief_version: 1 }, key: "demo-workroom-offer-v1")
  Marketplace::AwardProposal.call(actor: client, project: project.reload, proposal_id: proposal.fetch(:id), brief_version: 1, key: "demo-workroom-award-v1")
end
engagement = Engagements::Engagement.find_by!(source_award_id: Marketplace::Award.find_by!(project_id: project.id).id)

# Initialize once, then preserve the participant's actions on every later seed run.
unless engagement.submissions.exists?
  Platform::Current.set(actor_id: creator.id, correlation_id: SecureRandom.uuid) do
    Engagements::StartWork.call(actor: creator, engagement: engagement, key: "demo-workroom-start") if engagement.state == "agreed"
    first_file = Engagements::WorkFile.create!(engagement: engagement, creator: creator, sha256: Digest::SHA256.file(Rails.root.join("../web/public/images/projects/brand-paper.png")).hexdigest)
    File.open(Rails.root.join("../web/public/images/projects/brand-paper.png"), "rb") { |file| first_file.file.attach(io: file, filename: "NORA_direction_v1.png", content_type: "image/png") }
    first = Engagements::SubmitWork.call(actor: creator, engagement: engagement.reload, content: "Первое направление: спокойная типографика, тёплая палитра и тактильные носители. Материалы — демонстрационные изображения MESH.", title: "NORA — первое направление", file_ids: [ first_file.id ], key: "demo-workroom-v1")
    Platform::Current.set(actor_id: client.id) do
      Engagements::RecordFeedback.call(actor: client, engagement: engagement.reload, content: "Нравится направление. Давайте сделаем знак чуть менее геометричным и добавим больше примеров упаковки.", submission_id: first.fetch(:id), kind: "changes_requested", key: "demo-workroom-feedback-v1")
    end
    files = [ [ "coffee-identity", "NORA_identity_v2.png" ], [ "brand-paper", "NORA_packaging_v2.png" ], [ "cafe-space", "NORA_space_v2.png" ] ].map do |image, filename|
      path = Rails.root.join("../web/public/images/projects/#{image}.png")
      item = Engagements::WorkFile.create!(engagement: engagement, creator: creator, sha256: Digest::SHA256.file(path).hexdigest)
      File.open(path, "rb") { |file| item.file.attach(io: file, filename: filename, content_type: "image/png") }
      item.id
    end
    Engagements::SubmitWork.call(actor: creator, engagement: engagement.reload, title: "NORA Brand Identity", content: "Обновил типографику, сделал знак мягче и добавил варианты упаковки. Показал, как система работает в пространстве и на носителях. Жду вашего фидбэка!\n\nВо вложении — демонстрационные материалы MESH для просмотра рабочего сценария.", file_ids: files, key: "demo-workroom-v2")
  end
end
puts "Workspace preview: /workspace?engagement=#{engagement.id} (design@mesh.local). Files use the normal scanner."
