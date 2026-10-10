class PublishingValidationJob < ApplicationJob
  queue_as :default

  def perform(validation_id)
    Publishing::ValidateCandidate.call(validation_id: validation_id, scanner: Talent::FileScanner.method(:scan))
  end
end
