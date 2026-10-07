module Api
  module V1
    class CreatorsController < ApplicationController
      skip_before_action :require_account!, only: :index

      def index
        render json: { data: Talent::Directory.search(query: params[:q]).map { |profile| Presenters.profile(profile) } }
      end

      def mine
        profile = Talent::Profile.find_by(account_id: current_account.id)
        render json: { profile: profile && Presenters.profile(profile) }
      end

      def create
        input = params.require(:profile).permit(:headline, :bio, :rate_minor, :currency, skills: [])
        profile = Talent::Profile.find_or_initialize_by(account_id: current_account.id)
        profile.update!(input)
        render json: Presenters.profile(profile)
      end
    end
  end
end
