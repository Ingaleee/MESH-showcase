module Marketplace
  class Project < Platform::Record
    self.table_name = "marketplace_projects"
    belongs_to :client, class_name: "Identity::Account"
    has_many :proposals, class_name: "Marketplace::Proposal"
    BRIEF_FIELDS = %w[title description category budget_minor currency deadline expected_result deliverables requirements skills reference_urls].freeze
    validates :title, presence: true, length: { maximum: 160 }
    validates :description, presence: true, length: { maximum: 10000 }
    validates :category, inclusion: { in: [ "Тексты", "Дизайн", "Видео", "Разработка", "Маркетинг" ] }
    validates :budget_minor, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 100_000_000_000 }
    validates :currency, inclusion: { in: Platform::Money::CURRENCIES.keys }
    validates :deadline, presence: true
    validates :expected_result, length: { maximum: 3000 }
    validate :structured_brief_is_valid

    def brief_snapshot
      attributes.slice(*BRIEF_FIELDS, "brief_version")
    end

    private

    def structured_brief_is_valid
      { deliverables: [ 20, 500 ], requirements: [ 20, 500 ], skills: [ 20, 80 ], reference_urls: [ 10, 2048 ] }.each do |field, (count, length)|
        values = public_send(field)
        unless values.is_a?(Array) && values.size <= count && values.all? { |value| value.is_a?(String) && value.present? && value.length <= length }
          errors.add(field, "contains invalid or excessive items")
        end
      end
      Array(reference_urls).each do |url|
        next unless url.is_a?(String)

        uri = URI.parse(url)
        errors.add(:reference_urls, "must contain public HTTP or HTTPS links without credentials") unless uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.nil?
      rescue URI::InvalidURIError
        errors.add(:reference_urls, "contains an invalid URL")
      end
    end
  end
end
