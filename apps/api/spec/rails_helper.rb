ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
abort "Specs require the dedicated mesh_test database." unless Rails.env.test? && ActiveRecord::Base.connection_db_config.database == "mesh_test"

require "rspec/rails"
require "factory_bot_rails"
require "spec_helper"
Rails.root.glob("spec/support/**/*.rb").sort.each { |file| require file }

RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods
  config.include WorkflowHelpers
  config.use_transactional_fixtures = false
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
  config.before do
    connection = ActiveRecord::Base.connection
    tables = connection.tables.select { |name| name.match?(/\A(identity_|talent_|marketplace_|engagements_|finance_|platform_|notifications_|publishing_|active_storage_)/) }
    connection.execute("TRUNCATE #{tables.map { |name| connection.quote_table_name(name) }.join(', ')} RESTART IDENTITY CASCADE")
    ActiveJob::Base.queue_adapter = :test
    Platform::Current.reset
  end
end
