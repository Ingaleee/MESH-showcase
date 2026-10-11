module Notifications
  class ConsumeEvent
    TITLES = {
      "project.published" => "Проект опубликован",
      "proposal.submitted" => "Новый отклик",
      "engagement.created" => "Автор выбран",
      "work.submitted" => "Передана новая версия работы",
      "work.comment" => "Новый комментарий к работе",
      "work.changes_requested" => "Заказчик запросил изменения",
      "work.accepted" => "Работа принята",
      "payment.confirmed" => "Платёж подтверждён",
      "payment.failed" => "Платёж отклонён",
      "settlement.held" => "Выплата приостановлена"
    }.freeze

    def self.call(event)
      unless event.schema_version == 1
        raise Platform::Error.new("UNSUPPORTED_EVENT_VERSION", "Unsupported event version.")
      end
      event.payload.fetch("audience").map do |account_id|
        Notification.create_or_find_by!(account_id: account_id, outbox_event_id: event.id) do |notification|
          notification.title = TITLES.fetch(event.event_type)
          notification.body = event.payload.fetch("title").first(160)
          notification.resource_path = if event.payload["engagement_id"]
            "/workspace?engagement=#{event.payload['engagement_id']}"
          else
            "/projects/#{event.payload.fetch('project_id')}"
          end
        end
      end
    end
  end
end
