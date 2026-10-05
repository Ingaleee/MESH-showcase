if Rails.env.development?
  password = "MeshDemo2026!"
  client = Identity::Account.find_or_create_by!(email: "client@mesh.local") do |account|
    account.assign_attributes(display_name: "Анна / Studio North", persona: "client", password: password)
  end
  Identity::Account.find_or_create_by!(email: "ops@mesh.local") do |account|
    account.assign_attributes(display_name: "Оператор MESH", persona: "client", operator: true, password: password)
  end

  creators = [
    [ "creator@mesh.local", "Саша Волкова", "Редактор и автор сложных историй", "Помогаю брендам найти свой голос. Пишу понятно, исследую глубоко и всегда начинаю с вопроса «зачем?».", [ "Редактура", "UX-тексты", "Интервью" ], 3500000, "#eee6fa" ],
    [ "design@mesh.local", "Марк Соколов", "Бренд-дизайнер с вниманием к смыслу", "Превращаю характер бизнеса в визуальную систему. От первого эскиза до работающих носителей.", [ "Айдентика", "Типографика", "Figma" ], 8500000, "#f8e8dc" ],
    [ "video@mesh.local", "Лера Орлова", "Режиссёр монтажа и визуальный рассказчик", "Собираю истории, которые хочется досмотреть. Люблю документальный подход и точный ритм.", [ "Монтаж", "Motion", "Сторителлинг" ], 6000000, "#e1eee7" ],
    [ "dev@mesh.local", "Илья Мельников", "Разработчик цифровых продуктов", "Делаю быстрые интерфейсы и понятные сервисы. Внимательно отношусь к деталям и будущему продукта.", [ "React", "TypeScript", "Продукт" ], 12000000, "#e5eafa" ],
    [ "strategy@mesh.local", "Даша Миронова", "Стратег и исследователь брендов", "Нахожу связи между аудиторией, продуктом и коммуникацией. Хорошая стратегия начинается с наблюдений.", [ "Стратегия", "Исследования", "Контент" ], 7000000, "#f6e3ee" ],
    [ "illustration@mesh.local", "Никита Лис", "Иллюстратор с собственным почерком", "Создаю живые изображения для брендов, книг и цифровых продуктов. От маленькой детали до целого мира.", [ "Иллюстрация", "Арт-дирекшн", "Обложки" ], 4500000, "#eee7da" ]
  ]
  creators.each do |email, name, headline, bio, skills, rate, accent|
    account = Identity::Account.find_or_create_by!(email: email) do |row|
      row.assign_attributes(display_name: name, persona: "creator", password: password)
    end
    Talent::Profile.find_or_create_by!(account_id: account.id) do |profile|
      profile.assign_attributes(headline: headline, bio: bio, skills: skills, rate_minor: rate, accent: accent)
    end
  end

  projects = [
    [ "Голос бренда для нового кофейного проекта", "Тексты", 4500000, "Нужны tone of voice, тексты для сайта и короткая история бренда. Мы открываем кофейню, в которой хочется остаться подольше. Результат: гайд по голосу бренда и 8 готовых текстов." ],
    [ "Айдентика студии современной керамики", "Дизайн", 12000000, "Создадим узнаваемую визуальную систему для мастерской ручной керамики. Нужны знак, палитра, типографика и упаковка. Критерии приёмки: исходники и гайд по применению." ],
    [ "Короткий фильм о людях и их деле", "Видео", 8000000, "Три героя, три маленьких бизнеса, одна история. Ищем автора монтажа для документального ролика на 3 минуты. Исходники предоставим; итог — фильм и три коротких версии." ],
    [ "Лендинг для независимого книжного клуба", "Разработка", 9500000, "Нужен быстрый и доступный сайт с календарём встреч и формой записи. Дизайн уже готов. Приёмка: адаптивные страницы, работающая форма и инструкция по обновлению." ],
    [ "Контент-стратегия для локального бренда", "Маркетинг", 6000000, "Помогите рассказать о марке одежды без рекламного шума. Ждём исследование аудитории, три направления коммуникации и план публикаций на месяц." ],
    [ "Серия иллюстраций для городского путеводителя", "Дизайн", 5500000, "Десять мест, которые любят местные. Нужны иллюстрации с характером для печатного и цифрового путеводителя. Итог: 10 согласованных иллюстраций в двух форматах." ]
  ]
  Platform::Current.set(actor_id: client.id, correlation_id: SecureRandom.uuid) do
    projects.each_with_index do |(title, category, budget, description), index|
      next if Platform::IdempotencyRecord.exists?(actor_id: client.id, operation: "create_project", key: "demo-project-#{index}")
      Marketplace::CreateProject.call(
        actor: client, key: "demo-project-#{index}",
        input: { title: title, category: category, budget_minor: budget, currency: "RUB", description: description, deadline: 45.days.from_now.to_date }
      )
    end
  end
  Platform::Current.set(actor_id: client.id, correlation_id: SecureRandom.uuid) do
    unless Platform::IdempotencyRecord.exists?(actor_id: client.id, operation: "create_project", key: "demo-coffee-brief-v1")
      Marketplace::CreateProject.call(
        actor: client, key: "demo-coffee-brief-v1",
        input: {
          title: "Айдентика для кофейного бренда", category: "Дизайн", budget_minor: 12000000, currency: "RUB", deadline: 21.days.from_now.to_date,
          description: "Создаём визуальную идентичность NORA — нового кофейного проекта. Ищем дизайнера, который чувствует атмосферу места и умеет превращать её в сильный визуальный язык.\n\nНужно передать характер современной, тёплой и осознанной кофейни: здесь встречаются, работают и остаются подольше. Важно, чтобы система была узнаваемой и в пространстве, и на упаковке, и в цифровых каналах.",
          expected_result: "Цельная и гибкая айдентика, которая одинаково хорошо работает в кофейне и онлайн. На выходе ждём согласованные макеты, редактируемые исходники, файлы для печати и понятный гайд для команды. Финальные решения должны сохранять читаемость на небольших носителях.",
          deliverables: [ "Логотип и визуальная концепция бренда", "Фирменные цвета, типографика и графические элементы", "Упаковка: стаканы, пакеты и стикеры", "Базовые носители: меню, вывеска и шаблоны для социальных сетей", "Гайдлайн с правилами использования и исходные файлы" ],
          requirements: [ "Портфолио с примерами айдентики и упаковки", "Умение объяснять решения через характер бренда и задачу бизнеса", "Опыт подготовки макетов к печати", "Готовность обсуждать промежуточные решения и фиксировать согласования" ],
          skills: [ "Брендинг", "Логотип", "Фирменный стиль", "Упаковка", "Гайдлайн", "Графический дизайн" ], reference_urls: []
        }
      )
    end
  end
  load Rails.root.join("db/seeds/owner_preview.rb")
  load Rails.root.join("db/seeds/workspace_preview.rb")
  puts "Demo ready: client@mesh.local, creator@mesh.local, ops@mesh.local / #{password}"
end
