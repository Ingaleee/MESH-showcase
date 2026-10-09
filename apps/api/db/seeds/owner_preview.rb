require "digest"

# A separate demo keeps the public brief and author composer available for review.
client = Identity::Account.find_by!(email: "client@mesh.local")
marker = Platform::IdempotencyRecord.find_by(actor_id: client.id, operation: "create_project", key: "demo-owner-coffee-v1")
project = if marker
  Marketplace::Project.find(marker.response.fetch("id"))
else
  source = Marketplace::Project.find_by!(title: "Айдентика для кофейного бренда", client_id: client.id)
  input = source.brief_snapshot.except("brief_version").symbolize_keys.merge(
    title: "Айдентика для кофейного бренда NORA", deadline: 21.days.from_now.to_date
  )
  Platform::Current.set(actor_id: client.id, correlation_id: SecureRandom.uuid) do
    Marketplace::Project.find(Marketplace::CreateProject.call(actor: client, input: input, key: "demo-owner-coffee-v1").fetch(:id))
  end
end

offers = [
  [ "design@mesh.local", 9500000, 18, "brand-paper", "Начну с исследования характера NORA и предложу две визуальные концепции. Выбранное направление проверю на стакане, меню и вывеске. В стоимость входят логотип, фирменные цвета и шрифты, упаковка, базовые носители и гайд для команды.\n\nПередам исходники и печатные макеты. Вложение — демонстрационный пример визуального направления MESH." ],
  [ "strategy@mesh.local", 11000000, 14, "cafe-space", "Предлагаю начать с позиционирования: кто наши гости и почему они захотят остаться. Затем оформим характер бренда в визуальную систему совместно с дизайнером.\n\nВключены исследование аудитории, платформа бренда, визуальные принципы и рекомендации для пространства. Пример атмосферы во вложении — демонстрационный материал MESH." ],
  [ "illustration@mesh.local", 8500000, 21, "coffee-identity", "Вижу NORA как место с собственным почерком. Предложу авторскую графику, которая объединит упаковку, меню и цифровые носители.\n\nДве концепции, один выбранный стиль, иллюстрации и правила применения. Макеты для печати и исходники входят в стоимость. Во вложении — демонстрационный пример MESH." ],
  [ "dev@mesh.local", 12000000, 16, "brand-paper", "Помогу продолжить визуальную систему в цифровой среде: подготовлю компоненты и адаптивную витрину кофейни. Начнём с согласования структуры, затем соберём прототип и проверим его на телефоне.\n\nЭто предложение покрывает цифровые носители; полноценный брендинг потребует участия дизайнера. Во вложении — демонстрационный материал MESH." ]
]

if project.state == "open" && project.accepting_proposals && project.brief_version == 1
  offers.each do |email, price, days, image, message|
    creator = Identity::Account.find_by!(email: email)
    next if Marketplace::Proposal.exists?(project_id: project.id, creator_id: creator.id, brief_version: 1)

    path = Rails.root.join("../web/public/images/projects/#{image}.png")
    sha256 = Digest::SHA256.file(path).hexdigest
    example = Marketplace::ProposalExample.find_or_create_by!(project: project, creator: creator, proposal_id: nil, sha256: sha256)
    unless example.file.attached?
      File.open(path, "rb") { |file| example.file.attach(io: file, filename: "#{image}-demo.png", content_type: "image/png") }
    end
    Platform::Current.set(actor_id: creator.id, correlation_id: SecureRandom.uuid) do
      Marketplace::SubmitProposal.call(
        actor: creator, project: project.reload, key: "demo-owner-offer-v1",
        input: { price_minor: price, delivery_days: days, message: message, brief_version: 1, example_id: example.id }
      )
    end
  end
end
puts "Owner preview: /projects/#{project.id} (client@mesh.local). Examples use the normal quarantine/scan pipeline."
