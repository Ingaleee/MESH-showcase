module Engagements
  class EngagementPolicy < Platform::Policy
    def show?
      actor && [ record.client_id, record.creator_id ].include?(actor.id)
    end
    def submit?
      record.creator_id == actor&.id
    end
    def accept?
      record.client_id == actor&.id
    end
    class Scope
      def initialize(actor, scope)
        @actor, @scope = actor, scope
      end
      def resolve
        @scope.where(client_id: @actor.id).or(@scope.where(creator_id: @actor.id))
      end
    end
  end
end
