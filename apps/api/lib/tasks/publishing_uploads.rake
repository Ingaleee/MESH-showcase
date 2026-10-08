namespace :publishing do
  namespace :uploads do
    desc "Inspect abandoned uploads; APPLY=1 reclaims after the backup grace period"
    task reclaim: :environment do
      grace = Integer(ENV.fetch("GRACE_DAYS", "2")).days
      result = Publishing::ReclaimUploads.call(dry_run: ENV["APPLY"] != "1", grace: grace,
        limit: Integer(ENV.fetch("LIMIT", "100")))
      puts JSON.pretty_generate(result)
    end
  end
end
