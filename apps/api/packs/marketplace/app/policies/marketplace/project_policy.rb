module Marketplace
  class ProjectPolicy < Platform::Policy
    def show?
      record.state == "open" || record.client_id == actor&.id || record.proposals.exists?(creator_id: actor&.id)
    end
    def update?
      record.client_id == actor&.id
    end
    alias_method :award?, :update?
    def propose?
      authenticated? && record.client_id != actor.id && record.state == "open"
    end
    class Scope
      def initialize(actor, scope)
        @actor, @scope = actor, scope
      end
      def resolve
        return @scope.where(state: "open") unless @actor
        @scope.where(state: "open").or(@scope.where(client_id: @actor.id)).or(
          @scope.where(id: Proposal.where(creator_id: @actor.id).select(:project_id))
        )
      end
    end
  end
end
