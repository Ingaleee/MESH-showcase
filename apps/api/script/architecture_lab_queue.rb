require_relative "../config/environment"
require_relative "support/architecture_lab"

ArchitectureLab.guard!
state = ArchitectureLab.state
engagement = Engagements::Engagement.find(state.fetch("engagement_id"))
emit = lambda do
  Platform::Record.transaction do
    Platform::Events.emit(type: "work.submitted", aggregate: engagement, payload: {
      audience: [ engagement.client_id ], title: "Lab durable event", engagement_id: engagement.id
    })
  end
end
case ARGV.fetch(0)
when "burst"
  state["burst_event_ids"] = 50.times.map { emit.call.id }
  ArchitectureLab.save_state(state)
  OutboxDispatcher.call
  snapshot = QueueMetrics.snapshot
  raise "Real Solid Queue backlog was not created" unless snapshot[:rows].any? { |row| row["state"] == "ready" && row["count"].to_i >= 50 }
  ArchitectureLab.report("queue-backlog", snapshot.merge(events: 50, worker_stopped: true))
when "drain"
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  ids = state.fetch("burst_event_ids")
  ArchitectureLab.wait { Platform::Delivery.where(outbox_event_id: ids, state: "processed").count == ids.size }
  counts = Notifications::Notification.where(outbox_event_id: ids).group(:outbox_event_id).count
  raise "Duplicate or missing notification effect" unless counts.size == 50 && counts.values.all? { |value| value == 1 }
  ArchitectureLab.report("queue-drained", QueueMetrics.snapshot.merge(processed: ids.size, effects_per_event: counts.values.uniq, drain_wait_seconds: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(3)))
when "outage"
  event = emit.call
  target = URI(ENV.fetch("QUEUE_DATABASE_URL"))
  target.port = 65432
  SolidQueue::Record.establish_connection(target.to_s)
  OutboxDispatcher.call
  delivery = Platform::Delivery.find_by!(outbox_event_id: event.id)
  raise "Enqueue failure lost durable intent" unless delivery.state == "pending" && delivery.claim_token.nil? && delivery.last_error.present?
  snapshot = QueueMetrics.snapshot
  raise "Queue outage was reported as healthy" if snapshot[:available]
  state["outage_event_id"] = event.id
  state["outage_snapshot"] = snapshot
  ArchitectureLab.save_state(state)
  ArchitectureLab.report("queue-outage-pending", { unavailable_snapshot: snapshot, state: delivery.state, claim_cleared: delivery.claim_token.nil?, error_recorded: delivery.last_error.present? })
when "recover-outage"
  event_id = state.fetch("outage_event_id")
  delivery = Platform::Delivery.find_by!(outbox_event_id: event_id)
  ArchitectureLab.wait { delivery.reload.state == "processed" }
  raise "Enqueue recovery duplicated notification" unless Notifications::Notification.where(outbox_event_id: event_id).count == 1
  ArchitectureLab.report("queue-outage", { unavailable_snapshot: state.fetch("outage_snapshot"), durable_intent_preserved: true, state_after: delivery.state, notifications: 1, failure: "The lab dispatcher is stopped while an isolated producer connects to a closed queue PostgreSQL port; after the failed enqueue, the healthy dispatcher resumes. The shared PostgreSQL server stays running." })
when "poison"
  event = Platform::Record.transaction do
    bad = Platform::OutboxEvent.create!(event_type: "work.submitted", aggregate_type: engagement.class.name, aggregate_id: engagement.id,
      aggregate_version: 0, schema_version: 999, payload: { audience: [ engagement.client_id ], title: "Poison fixture", engagement_id: engagement.id }, correlation_id: SecureRandom.uuid)
    Platform::Delivery.create!(outbox_event: bad, consumer: "notifications")
    bad
  end
  delivery = Platform::Delivery.find_by!(outbox_event_id: event.id)
  ArchitectureLab.wait { delivery.reload.state == "failed" }
  raise "Poison event exceeded retry budget" unless delivery.failure_count == 5
  raise "Poison event produced an effect" if Notifications::Notification.exists?(outbox_event_id: event.id)
  ArchitectureLab.report("queue-poison", QueueMetrics.snapshot.merge(state: delivery.state, failures: delivery.failure_count, attempts: delivery.attempts, notifications: 0, last_error: delivery.last_error))
when "backup-lease"
  event = emit.call
  OutboxDispatcher.call
  delivery = Platform::Delivery.find_by!(outbox_event_id: event.id)
  raise "Fixture must be enqueued before queue loss" unless delivery.state == "enqueued"
  state["recovery_event_id"] = event.id
  state["recovery_claim_token"] = delivery.claim_token
  ArchitectureLab.save_state(state)
when "recover"
  delivery = Platform::Delivery.find_by!(outbox_event_id: state.fetch("recovery_event_id"))
  ArchitectureLab.wait { delivery.reload.state == "processed" }
  count = Notifications::Notification.where(outbox_event_id: state.fetch("recovery_event_id")).count
  raise "Restored queue loss duplicated or lost an effect" unless count == 1
  ArchitectureLab.report("restored-queue", { processed: true, notifications: count, claim_cleared: delivery.claim_token.nil?, fresh_queue: true, attempts: delivery.attempts, payouts_disabled: true })
else
  raise "Invalid queue exercise"
end
puts "Queue exercise completed."
